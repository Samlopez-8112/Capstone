import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/encryption_service.dart';
import '../offline_maps/offline_maps_page';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

//default slider values
double _drivingSliderValue = 1;
double _bikingSliderValue = 3;
double _walkingSliderValue = 4;

class _SettingsScreenState extends State<SettingsScreen> {
  final _auth = FirebaseAuth.instance;
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _displayNameController;
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  TextEditingController _phoneController = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    _displayNameController = TextEditingController(text: user?.displayName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    final user = _auth.currentUser;
      if (user == null) return;

      setState(() => _loading = true);

      try {
        // Update Firebase Auth profile (not encrypted)
        await user.updateDisplayName(_displayNameController.text);
        if (_emailController.text != user.email) {
          await user.updateEmail(_emailController.text);
        }
        if (_passwordController.text.isNotEmpty) {
          await user.updatePassword(_passwordController.text);
        }

        // Encrypt sensitive fields
        final encryptedName = await EncryptionService.encrypt(_displayNameController.text);
        final encryptedEmail = await EncryptionService.encrypt(_emailController.text);
        //final encryptedPhone = await EncryptionService.encrypt(_phoneController.text.trim());

        // Save encrypted data to Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'full_name': encryptedName,
          'email': encryptedEmail,
          //'phone': encryptedPhone,
        });

        await user.reload();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );
      } on FirebaseAuthException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.message}')),
        );
        } finally {
          setState(() => _loading = false);
        }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(labelText: 'Display Name'),
                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                validator: (value) => value == null || !value.contains('@') ? 'Enter valid email' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password (optional)'),
                validator: (value) {
                  if(value != null && value.isNotEmpty && value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'Phone Number (+1234567890)'),
              ),

              const SizedBox(height: 24),
              Text(
                "Safety Tolerances",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),

              // driving slider
              SliderPreference(
                label: "Driving Safety Level",
                value: _drivingSliderValue,
                onChanged: (val) => setState(() => _drivingSliderValue = val),
              ),

              // biking slider
              SliderPreference(
                label: "biking Safety Level",
                value: _bikingSliderValue,
                onChanged: (val) => setState(() => _bikingSliderValue = val),
              ),

              // walking slider
              SliderPreference(
                label: "Walking Safety Level",
                value: _walkingSliderValue,
                onChanged: (val) => setState(() => _walkingSliderValue = val),
              ),

              ElevatedButton.icon(
                icon: const Icon(Icons.phone),
                label: const Text('Link Phone for MFA'),
                onPressed: _linkPhoneNumber,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save Changes'),
                onPressed: _saveChanges,
              ),

              //Offline Maps button
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: const Text('Offline Maps'),
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),                 // oval/pill
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OfflineMapsPage(),
                      ),
                    );
                  },
                ),
              ),
              // ----------------------------------------------------------------
            ],
          ),
        ),
      ),
    );
  }
void _linkPhoneNumber() async {
    final phone = _phoneController.text.trim();
      if (phone.isEmpty) return;

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone number linked as MFA')),
          );
        },
        verificationFailed: (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification failed: ${e.message}')),
          );
        },
        codeSent: (verificationId, resendToken) async {
          String? smsCode = await _askUserForSmsCode();
          if (smsCode == null) return;

          final credential = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: smsCode,
          );
          await FirebaseAuth.instance.currentUser?.linkWithCredential(credential);

          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MFA setup complete!')),
          );
        },
        codeAutoRetrievalTimeout: (_) {},
      );
  }

  Future<String?> _askUserForSmsCode() async {
    String? smsCode;
      await showDialog(
      context: context,
      builder: (context) {
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
              smsCode = codeController.text.trim();
              Navigator.of(context).pop();
            },
            child: const Text('Submit'),
          )
        ],
      );
    },
  );
  return smsCode;
}
}

class SliderPreference extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const SliderPreference({
    Key? key,
    required this.label,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Slider(
          value: value,
          min: 1,
          max: 5,
          divisions: 4, // makes ticks at 1–5
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}