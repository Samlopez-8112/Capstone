//Screen for sign-in and create account
//help from chatgpt

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import 'map_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'settings_screen.dart';
import '../services/encryption_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';


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

          await FirebaseFirestore.instance.collection('mail').add({
            'to': email,
            'message': {
              'subject': 'New Device Login Detected',
              'text': '''
Hello,

A new device just logged into your account.

Device ID: $deviceId
Time: ${DateTime.now().toUtc()}

If this was you, no action is needed.
If not, please reset your password immediately.

Stay safe, 
Bypassr Security Team
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

    final uid = userCred.user?.uid;
    final encryptedName = await EncryptionService.encrypt(displayName);
    final encryptedEmail = await EncryptionService.encrypt(email);
    final rawDeviceId = await getUniqieDeviceId();
    final encryptedDeviceId = await EncryptionService.encrypt(rawDeviceId);

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'full_name': encryptedName,
      'email': encryptedEmail,
      'created_at': Timestamp.now(),
    });
  }

  print("✅ Auth successful");
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (_) => const MapPage()),
  );
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
              /*TextFormField(
                key: const ValueKey('phone'),
                decoration: const InputDecoration(labelText: 'Phone Number (+1234567890)'),
                keyboardType: TextInputType.phone,
                onSaved: (val) => phone = val!.trim(),
                validator: (val) {
                  if (val == null || val.isEmpty || !val.startsWith('+')) {
                    return 'Enter valid phone number with +';
                  }
                  return null;
                },
              ),*/
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
    /*void _linkPhoneNumberMfa(String phoneNumber) async {
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
          verificationCompleted: (PhoneAuthCredential credential) async {
            await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
            print('✅ Phone linked for MFA (auto)');
          },
          verificationFailed: (FirebaseAuthException e) {
            print('❌ Phone verification failed: ${e.message}');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Phone verification failed: ${e.message}')),
            );
          },
          codeSent: (verificationId, resendToken) async {
            final smsCode = await _askUserForSmsCode();
            if (smsCode == null) return;

            final credential = PhoneAuthProvider.credential(
              verificationId: verificationId,
              smsCode: smsCode,
            );

            await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Phone linked as MFA second factor!')),
              );
          },
            codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
        print('⚠️ MFA linking error: $e');
      }
    }

    Future<String?> _askUserForSmsCode() async {
      String? code;
        await showDialog(
          context: context,
          builder: (ctx) {
          final codeController = TextEditingController();
            return AlertDialog(
                title: const Text('Enter SMS Code'),
                content: TextField(
                  controller: codeController,
                  keyboardType: TextInputType.number,
                ),
              actions: [
                TextButton(
                  onPressed: () {
                    code = codeController.text.trim();
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Submit'),
                )
              ],
            );
          },
        );
        return code;
    }*/
}

