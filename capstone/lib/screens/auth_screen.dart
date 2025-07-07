//Screen for sign-in and create account
//help from chatgpt

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/firestore_service.dart';
import 'home_page.dart';

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

  void submit() async {
    if(!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    try{
      UserCredential userCred;
      if(isLogin){
        userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email, password: password,
        );
      }else{
        userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email, 
        password: password,
        );
        await writeUserProfile(displayName: displayName, 
        email: email, 
        photoURL: null,
        );
      }
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } catch (e){
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
}

