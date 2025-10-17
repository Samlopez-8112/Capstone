import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/encryption_service.dart';
import '../offline_maps/offline_maps_page.dart';

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
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save Changes'),
                onPressed: _saveChanges,
              ),

              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete Account'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: _confirmDeleteAccount,
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

void _confirmDeleteAccount() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm Deletion'),
      content: const Text('This will permanently delete your account and data. Are you sure?'),
      actions: [
        TextButton(child: const Text('Cancel'),
        onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          child: const Text('Delete'),
          onPressed: () {
            Navigator.pop(context);
            _deleteAccount();
          },
          ),
      ],
    )
  );
}

Future<void> _deleteAccount() async {
  final user = _auth.currentUser;
  if(user == null) return;

  setState(() => _loading = true);

  try{
    //Delete Firestore user data
    await FirebaseFirestore.instance.collection('users')
    .doc(user.uid).delete();

    //Delete Auth account
    await user.delete();

    //Optionally sign out and redirect
    await _auth.signOut();
    if(context.mounted){
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  } on FirebaseAuthException catch (e){
    if(e.code == 'requires-recent-login'){
        final success = await _reauthenticateUser();
        if(success){
          _deleteAccount();
        } else{
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reauthentication failed')),
          );
        }
      //Prompt for reauthentication here if needed
    } else{
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting account: ${e.message}')),
      );
    }
  } finally{
    setState(() => _loading = false);
  }
}

  Future<bool> _reauthenticateUser() async {
  final passwordController = TextEditingController();
  final user = _auth.currentUser;

  if (user?.email == null) return false;

  return await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Re-enter Password'),
      content: TextField(
        controller: passwordController,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final password = passwordController.text.trim();
            final credential = EmailAuthProvider.credential(
              email: user!.email!,
              password: password,
            );
            try {
              await user.reauthenticateWithCredential(credential);
              Navigator.of(context).pop(true);
            } on FirebaseAuthException catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Reauth failed: ${e.message}')),
              );
              Navigator.of(context).pop(false);
            }
          },
          child: const Text('Confirm'),
        ),
      ],
    ),
  ) ?? false;
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