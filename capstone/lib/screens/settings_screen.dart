import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/encryption_service.dart';
import '../offline_maps/offline_maps_page.dart';
import 'package:provider/provider.dart';
import '../theme_manager.dart'; // Import ThemeManager
import '../screens/auth_screen.dart';

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
  //TextEditingController _phoneController = TextEditingController();

  bool _loading = false;

  // tri-state safety preferences: null = neutral, true = prefer, false = avoid
  Map<String, bool?> _safetyPreferences = {
    'Well-lit': null,
    'Police presence': null,
    'Quiet at night': null,
    'Busy foot traffic': null,
    'Loitering': null,
    'Graffiti/vandalism': null,
    'Poor lighting': null,
    'Suspicious activity': null,
    'Reports of crime': null,
    'Clean and maintained': null,
    'Security cameras': null,
    'Active neighborhood watch': null,
    'Nearby schools or parks': null,
    'Frequent police sirens': null,
    'Abandoned buildings': null,
    'Shops open late': null,
  };

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

      // Save encrypted data to Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'full_name': encryptedName,
        'email': encryptedEmail,
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
    final themeManager = Provider.of<ThemeManager>(context); // ✅ Access theme manager

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------------- PROFILE SETTINGS ----------------
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
                  if (value != null && value.isNotEmpty && value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),

              // ---------------- THEME SWITCH SECTION ----------------
              const SizedBox(height: 30),
              const Text(
                "App Theme",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              RadioListTile<AppThemeMode>(
                title: const Text('Light'),
                value: AppThemeMode.light,
                groupValue: themeManager.appThemeMode,
                onChanged: (value) => themeManager.setThemeMode(value!),
              ),
              RadioListTile<AppThemeMode>(
                title: const Text('Dark'),
                value: AppThemeMode.dark,
                groupValue: themeManager.appThemeMode,
                onChanged: (value) => themeManager.setThemeMode(value!),
              ),
              RadioListTile<AppThemeMode>(
                title: const Text('Automatic'),
                value: AppThemeMode.automatic,
                groupValue: themeManager.appThemeMode,
                onChanged: (value) => themeManager.setThemeMode(value!),
              ),

              // ---------------- SAFETY SLIDERS ----------------
              const SizedBox(height: 30),
              const Text(
                "Safety Tolerances",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SliderPreference(
                label: "Driving Safety Level",
                value: _drivingSliderValue,
                onChanged: (val) => setState(() => _drivingSliderValue = val),
              ),
              SliderPreference(
                label: "Biking Safety Level",
                value: _bikingSliderValue,
                onChanged: (val) => setState(() => _bikingSliderValue = val),
              ),
              SliderPreference(
                label: "Walking Safety Level",
                value: _walkingSliderValue,
                onChanged: (val) => setState(() => _walkingSliderValue = val),
              ),

              const SizedBox(height: 12),
              // --- Prefer areas with (tri-state checkboxes) ---
              const Text(
                'Prefer areas with:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Column(
                children: [
                  _TriStateRow(label: 'Well-lit'),
                  _TriStateRow(label: 'Police presence'),
                  _TriStateRow(label: 'Quiet at night'),
                  _TriStateRow(label: 'Busy foot traffic'),
                  _TriStateRow(label: 'Loitering'),
                  _TriStateRow(label: 'Graffiti/vandalism'),
                  _TriStateRow(label: 'Poor lighting'),
                  _TriStateRow(label: 'Suspicious activity'),
                  _TriStateRow(label: 'Reports of crime'),
                  _TriStateRow(label: 'Clean and maintained'),
                  _TriStateRow(label: 'Security cameras'),
                  _TriStateRow(label: 'Active neighborhood watch'),
                  _TriStateRow(label: 'Nearby schools or parks'),
                  _TriStateRow(label: 'Frequent police sirens'),
                  _TriStateRow(label: 'Abandoned buildings'),
                  _TriStateRow(label: 'Shops open late'),
                ],
              ),


              // ---------------- ACTION BUTTONS ----------------
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save Changes'),
                onPressed: _saveChanges,
              ),

              const SizedBox(height:24),
ElevatedButton.icon(
  icon: const Icon(Icons.logout),
  label: const Text('Log Out'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    elevation: 2,
  ),
  onPressed: () async {
    await FirebaseAuth.instance.signOut();

    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  },
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

              // ---------------- OFFLINE MAPS ----------------
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: const Text('Offline Maps'),
                  style: ElevatedButton.styleFrom(
                    shape: const StadiumBorder(),
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
          TextButton(
            child: const Text('Cancel'),
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
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      await user.delete();
      await _auth.signOut();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        final success = await _reauthenticateUser();
        if (success) {
          _deleteAccount();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reauthentication failed')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: ${e.message}')),
        );
      }
    } finally {
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
        ) ??
        false;
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
          divisions: 4,
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}


class _TriStateRow extends StatefulWidget {
  final String label;
  const _TriStateRow({required this.label});

  @override
  State<_TriStateRow> createState() => _TriStateRowState();
}

class _TriStateRowState extends State<_TriStateRow> {
  void _toggleState() {
    final parent = context.findAncestorStateOfType<_SettingsScreenState>()!;
    parent.setState(() {
      final current = parent._safetyPreferences[widget.label];
      if (current == null) {
        parent._safetyPreferences[widget.label] = true; // prefer
      } else if (current == true) {
        parent._safetyPreferences[widget.label] = false; // avoid
      } else {
        parent._safetyPreferences[widget.label] = null; // back to neutral
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final parent = context.findAncestorStateOfType<_SettingsScreenState>()!;
    final value = parent._safetyPreferences[widget.label];

    Color fillColor() {
      if (value == true) return Colors.green;
      if (value == false) return Colors.red;
      return Colors.grey.shade400;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0), // <-- adds vertical spacing
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: _toggleState,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: fillColor(),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.black26),
              ),
              child: value == true
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : (value == false
                      ? const Icon(Icons.close, color: Colors.white, size: 18)
                      : null),
            ),
          ),
          const SizedBox(width: 12), // <-- adds horizontal space between box and label
          Expanded(
            child: Text(
              widget.label,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}