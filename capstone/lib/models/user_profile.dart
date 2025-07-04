import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String displayName;
  final String email;
  final String? photoURL;

  UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoURL,
  });

  Map<String, dynamic> toMap() => {
    'displayName': displayName,
    'email': email,
    'photoURL': photoURL,
    'createdAt': FieldValue.serverTimestamp(),
    'lastActive': FieldValue.serverTimestamp(),
  };
}
