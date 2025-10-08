import 'package:flutter/material.dart';

class LockedAccountScreen extends StatelessWidget{
  const LockedAccountScreen({super.key});

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: const Text('Account Locked')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Your account has been locked. You cannot use this account for this app.'
            'Please contact support if this was a mistake.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.red),
          ),
        ),
      ),
    );
  }
}