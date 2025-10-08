import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/LockedAccountScreen.dart';

class AccountLockGuard {
  static Future<void> check(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final locked = doc.data()?['accountLocked'] ?? false;
      if (locked && context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LockedAccountScreen()),
        );
      }
    } catch (e) {
      debugPrint('Error checking account lock: $e');
    }
  }
}
