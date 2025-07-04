import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final FirebaseFirestore firestore = FirebaseFirestore.instance;
final FirebaseAuth auth = FirebaseAuth.instance;

/// Write or update a user profile in Firestore
Future<void> writeUserProfile({
  required String displayName,
  required String email,
  String? photoURL,
}) async {
  final uid = auth.currentUser!.uid;
  await firestore.collection('users').doc(uid).set({
    'displayName': displayName,
    'email': email,
    'photoURL': photoURL,
    'createdAt': FieldValue.serverTimestamp(),
    'lastActive': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
}

/// Add a recent location under the user's document
Future<void> addRecentLocation({
  required String name,
  required double latitude,
  required double longitude,
  String? placeId,
}) async {
  final uid = auth.currentUser!.uid;
  await firestore
      .collection('users')
      .doc(uid)
      .collection('recent_locations')
      .add({
    'name': name,
    'placeId': placeId,
    'coordinates': GeoPoint(latitude, longitude),
    'visitedAt': FieldValue.serverTimestamp(),
  });
}

/// Add a favorite location under the user's document
Future<void> addFavoriteLocation({
  required String name,
  required double latitude,
  required double longitude,
  String? placeId,
  String? notes,
}) async {
  final uid = auth.currentUser!.uid;
  await firestore
      .collection('users')
      .doc(uid)
      .collection('favorite_locations')
      .add({
    'name': name,
    'placeId': placeId,
    'coordinates': GeoPoint(latitude, longitude),
    'notes': notes,
    'addedAt': FieldValue.serverTimestamp(),
  });
}
