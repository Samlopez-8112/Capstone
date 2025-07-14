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
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_searchController.text.trim())
          .get();

      setState(() {
        _foundUser = doc.exists ? doc : null;
      });
    } catch (e) {
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
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                            future: FirebaseFirestore.instance.collection('users')
                              .doc(currentUid).collection('shared_locations')
                              .doc(friendIds[index]).get(),
                            builder:(context, shareSnapshot) {
                              if(!shareSnapshot.hasData){
                                return const ListTile(title: Text("Loading sharing status..."));
                              }
                              final isSharing = shareSnapshot.data!.get('isSharing') ?? false;

                              return SwitchListTile(
                                title: Text(friendData.get('displayName') ?? 'No Display Name'),
                                subtitle: Text(friendIds[index]),
                                value: isSharing,
                                onChanged: (value) async {
                                  final ref = FirebaseFirestore.instance.collection('users')
                                    .doc(currentUid). collection('shared_locations')
                                    .doc(friendIds[index]);
                                  if(value) {
                                    await ref.set({
                                      'isSharing': true,
                                      'timestamp': FieldValue.serverTimestamp(),
                                    });
                                  } else{
                                    await ref.delete();
                                  }
                                  setState(() {}); //force UI refresh 
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
            )
          ],
        ),
      ),
    );
  }
}
