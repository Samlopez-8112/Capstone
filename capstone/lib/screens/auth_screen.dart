//Screen for sign-in and create account
//help from chatgpt

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'map_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/encryption_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../screens/LockedAccountScreen.dart';


class AuthScreen extends StatefulWidget{
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>{
  final _formKey = GlobalKey<FormState>();
  bool isLogin = true;
  String email = '', password = '', displayName = '';
  String error = '';
  //String phone = '';

  void submit() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    try {
      UserCredential userCred;
      if (isLogin) {
        // LOGIN FLOW
        print("🔐 Logging in user...");
        userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        final uid = userCred.user!.uid;
        final deviceId = await getUniqieDeviceId();

        final deviceRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('devices')
          .doc(deviceId);

        final deviceSnap = await deviceRef.get();

        if (!deviceSnap.exists) {
          await deviceRef.set({
            'deviceId': deviceId,
            'createAt': FieldValue.serverTimestamp(),
          });

        try {
          print("📧 Writing new mail doc to Firestore...");
          //final uid = userCred.user!.uid;
          //final encryptedUid = await EncryptionService.encrypt(uid);

          //final lockUrl = 'https://us-central1-capstoneproject-sf2025.cloudfunctions.net/lockAccount?uid=$encryptedUid';

          await FirebaseFirestore.instance.collection('mail').add({
            'to': email,
            'message': {
              'subject': 'New Device Login Detected',
              'html': '''
<p>Hello,</p>
<p>A new device just logged into your account.</p>
<p>Device ID: $deviceId<br/>
Time: ${DateTime.now().toUtc()}</p>

<p>If this wasn't you, please contact support at bypassr.support@gmail.com</p>

<p>Stay safe,<br/>Bypassr Security Team</p>
'''
          }
        });

        print('✅ Added email alert to /mail collection');
      } catch (e) {
        print("❌ Failed to add email doc: $e");
      }
    }
  } else {
  // SIGNUP FLOW
  print("🆕 Creating new user...");
  userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
    email: email,
    password: password,
  );

  final user = userCred.user;
  if (user == null) {
    print("❌ UID is null, cannot proceed");
    return;
  }
  final uid = user.uid;

  // Ensure encryption key exists before encrypting anything
  await EncryptionService.generateAndStoreKey();

  final encryptedName = await EncryptionService.encrypt(displayName);
  final encryptedEmail = await EncryptionService.encrypt(email);
  final rawDeviceId = await getUniqieDeviceId();
  final encryptedDeviceId = await EncryptionService.encrypt(rawDeviceId);

  print("🧾 Encrypted data ready. Writing Firestore docs...");

  try {
    // Store user profile
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'full_name': encryptedName,
      'email': encryptedEmail,
      'created_at': Timestamp.now(),
      'accountLocked': false,
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('devices')
      .doc(rawDeviceId)
      .set({
      'deviceId': rawDeviceId, // store raw, not encrypted
      'createdAt': FieldValue.serverTimestamp(),
      'firstLogin': true,
      });

    // ✅ Store device info in subcollection
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(rawDeviceId)
        .set({
      'deviceId': encryptedDeviceId,
      'createdAt': FieldValue.serverTimestamp(),
      'firstLogin': true,
    });

    print("✅ User + device document written to Firestore");

    // ✅ Optionally send “Welcome / new device registered” email
    try {
      //final encryptedUid = await EncryptionService.encrypt(uid);
      //final lockUrl =
          //'https://us-central1-capstoneproject-sf2025.cloudfunctions.net/lockAccount?uid=$encryptedUid';

      await FirebaseFirestore.instance.collection('mail').add({
        'to': email,
        'message': {
          'subject': 'Welcome to Bypassr — Your Account is Set Up',
          'html': '''
<p>Hello $displayName,</p>
<p>Your account has been created successfully.</p>
<p>Device ID: $rawDeviceId<br/>
Time: ${DateTime.now().toUtc()}</p>

<p>If this wasn't you, you can contact support at bypassr.support@gmail.com </a>.</p>

<p>Stay safe,<br/>Bypassr Security Team</p>
'''
        }
      });

      print('✅ Sent welcome email via Firestore mail trigger');
    } catch (e) {
      print("❌ Failed to add welcome email doc: $e");
    }

  } catch (e) {
    print("❌ Failed to write user or device document: $e");
  }

  // fetch user document
  final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final isLocked = (userDoc.data()?['accountLocked'] ?? false) as bool;

  if (isLocked) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LockedAccountScreen()),
    );
  } else {
    print("Auth successful");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MapPage()),
    );
  }
}

} catch (e, stack) {
  print("Auth error: $e");
  print(stack);
  if(!mounted) return;
  setState(() => error = e.toString());
}

   
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Login' : 'Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              if (!isLogin)
                TextFormField(
                  key: const ValueKey('displayName'),
                  decoration: const InputDecoration(labelText: 'Display Name'),
                  onSaved: (val) => displayName = val!.trim(),
                  validator: (val) => val!.isEmpty ? 'Required' : null,
                ),
              TextFormField(
                key: const ValueKey('email'),
                decoration: const InputDecoration(labelText: 'Email'),
                onSaved: (val) => email = val!.trim(),
                validator: (val) => val!.contains('@') ? null : 'Enter a valid email',
              ),
              TextFormField(
                key: const ValueKey('password'),
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                onSaved: (val) => password = val!,
                validator: (val) => val!.length < 6 ? '6+ chars' : null,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: submit,
                child: Text(isLogin ? 'Login' : 'Sign Up'),
              ),
              TextButton(
                onPressed: () => setState(() => isLogin = !isLogin),
                child: Text(isLogin ? 'Create account' : 'Already have an account?'),
              ),
              if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ),
    );
  }
  
  Future<String> getUniqieDeviceId() async{
    final deviceInfo = DeviceInfoPlugin();
    if(Platform.isAndroid){
      final android = await deviceInfo.androidInfo;
      return '${android.manufacturer}_${android.model}_${android.id}';
    }else if(Platform.isIOS){
      final ios = await deviceInfo.iosInfo;
      return '${ios.name}_${ios.systemVersion}_${ios.identifierForVendor}';
    }
    return 'unknown_device';
  }
}

