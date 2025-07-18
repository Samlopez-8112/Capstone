import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendScreen extends StatefulWidget {
  const FriendScreen({super.key});

  @override
  State<FriendScreen> createState() => _FriendScreenState();
}

class _FriendScreenState extends State<FriendScreen> {
  final TextEditingController _searchController = TextEditingController();
  DocumentSnapshot? _foundUser;
  final _auth = FirebaseAuth.instance;

void searchUserById() async {
  final searchId = _searchController.text.trim();
  final currentUid = _auth.currentUser!.uid;

  print("🔍 Searching for UID: $searchId");

  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(searchId)
        .get();

    print("Doc exists: ${doc.exists}");
    print("Data: ${doc.data()}");

    if (!doc.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No user found with that UID.")),
      );
      setState(() => _foundUser = null);
      return;
    }

    setState(() => _foundUser = doc);
  } catch (e) {
    print('Error: $e');
    setState(() => _foundUser = null);
  }
}




  Future<void> sendFriendRequest(String targetUid) async {
    final currentUid = _auth.currentUser!.uid;

    await FirebaseFirestore.instance.collection('friendships').add({
      'userA': currentUid,
      'userB': targetUid,
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend request sent')),
    );
  }

  Stream<List<String>> getFriendIdsStream() {
    final currentUid = _auth.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('friendships')
        .where('status', isEqualTo: 'accepted')
        .where('userA', isEqualTo: currentUid)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => doc['userB'] as String).toList());
  }

  Stream<List<DocumentSnapshot>> getIncomingRequestsStream() {
  final currentUid = _auth.currentUser!.uid;
  return FirebaseFirestore.instance
      .collection('friendships')
      .where('status', isEqualTo: 'pending')
      .where('userB', isEqualTo: currentUid)
      .snapshots()
      .map((snapshot) => snapshot.docs);
}

  @override
Widget build(BuildContext context) {
  final currentUid = _auth.currentUser!.uid;

  return Scaffold(
    appBar: AppBar(title: const Text('Friends')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Account ID: $currentUid',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search by Account ID (UID)',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: searchUserById,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_foundUser != null && _foundUser!.id != currentUid)
            ListTile(
              title: Text(_foundUser!.get('displayName') ?? 'No Name'),
              trailing: ElevatedButton(
                onPressed: () => sendFriendRequest(_foundUser!.id),
                child: const Text('Add Friend'),
              ),
            ),
          const SizedBox(height: 30),
          const Text('Incoming Friend Requests', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<List<DocumentSnapshot>>(
              stream: getIncomingRequestsStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final requests = snapshot.data!;
                if (requests.isEmpty) {
                  return const Center(child: Text("No pending requests"));
                }

                return ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final doc = requests[index];
                    final senderUid = doc['userA'];

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(senderUid).get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) {
                          return const ListTile(title: Text("Loading..."));
                        }

                        if (!userSnapshot.data!.exists) {
                          return ListTile(
                            title: Text("User not found"),
                            subtitle: Text(senderUid),
                          );
                        }

                        final senderData = userSnapshot.data!;
                        final senderName = senderData.get('displayName') ?? 'Unknown';

                        return ListTile(
                          title: Text(senderName),
                          subtitle: Text(senderUid),
                          trailing: ElevatedButton(
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection('friendships')
                                  .doc(doc.id)
                                  .update({'status': 'accepted'});
                            },
                            child: const Text("Accept"),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text('Your Friends', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 10),
          Expanded(
            child: StreamBuilder<List<String>>(
              stream: getFriendIdsStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final friendIds = snapshot.data!;
                if (friendIds.isEmpty) {
                  return const Center(child: Text("You have no friends yet"));
                }

                return ListView.builder(
                  itemCount: friendIds.length,
                  itemBuilder: (context, index) {
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(friendIds[index])
                          .get(),
                      builder: (context, userSnapshot) {
                        if (!userSnapshot.hasData) {
                          return const ListTile(title: Text('Loading...'));
                        }
                        final friendData = userSnapshot.data!;
                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(currentUid)
                              .collection('shared_locations')
                              .doc(friendIds[index])
                              .get(),
                          builder: (context, shareSnapshot) {
                            if (!shareSnapshot.hasData) {
                              return const ListTile(title: Text("Loading sharing status..."));
                            }
                            final isSharing = shareSnapshot.data!.get('isSharing') ?? false;

                            return SwitchListTile(
                              title: Text(friendData.get('displayName') ?? 'No Display Name'),
                              subtitle: Text(friendIds[index]),
                              value: isSharing,
                              onChanged: (value) async {
                                final ref = FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(currentUid)
                                    .collection('shared_locations')
                                    .doc(friendIds[index]);
                                if (value) {
                                  await ref.set({
                                    'isSharing': true,
                                    'timestamp': FieldValue.serverTimestamp(),
                                  });
                                } else {
                                  await ref.delete();
                                }
                                setState(() {});
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}


}
