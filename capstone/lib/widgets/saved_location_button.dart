import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SavedLocationButton extends StatelessWidget {
  const SavedLocationButton({super.key});

  Future<List<Map<String, dynamic>>> _fetchSavedLocations() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final snapshot = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("marked_locations")
        .orderBy("timestamp", descending: true)
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  void _showLocationsModal(BuildContext context) async {
    final locations = await _fetchSavedLocations();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return ListView.builder(
          itemCount: locations.length,
          itemBuilder: (_, index) {
            final loc = locations[index];
            return ListTile(
              leading: const Icon(Icons.place),
              title: Text('${loc["type"] ?? "Unknown"}'),
              subtitle: Text('Lat: ${loc["latitude"]}, Lng: ${loc["longitude"]}'),
              trailing: Text(
                loc["timestamp"]?.toDate()?.toString().split(".").first ?? "",
                style: const TextStyle(fontSize: 10),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return RawMaterialButton(
      onPressed: () => _showLocationsModal(context),
      elevation: 6.0,
      fillColor: const Color(0xFF007C91),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      constraints: const BoxConstraints.tightFor(width: 56, height: 56),
      child: const Icon(Icons.turn_right, color: Colors.white),
    );
  }
}
