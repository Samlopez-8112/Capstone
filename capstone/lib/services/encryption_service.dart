import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:encrypt/encrypt.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionService {
  static final _secureStorage = FlutterSecureStorage();
  static const _keyStorageKey = 'user_encryption_key';


//Generate a new AES 256-bit key and stores it securely
static Future<void> generateAndStoreKey() async {
  final key = Key.fromSecureRandom(32);
  final encodedKey = base64UrlEncode(key.bytes);
  await _secureStorage.write(key: _keyStorageKey, value: encodedKey);

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if(uid != null){
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'encryptionKey': encodedKey,
    }, SetOptions(merge:true));
  }
}

//Loads the AES key from secure storage
static Future<Key> _getKey() async {
  final encodedKey = await _secureStorage.read(key: _keyStorageKey);
  if(encodedKey == null) {
    throw Exception('Encryption Key not found. Call generateAndStoreKey() first');
  }
  return Key.fromBase64(encodedKey);
}

//Encrypts a plain text field and returns it as JSON string
static Future<String> encrypt(String plainText) async {
  final key = await _getKey();
  final iv = IV.fromSecureRandom(16);
  final encrypter = Encrypter(AES(key));
  final encrypted = encrypter.encrypt(plainText, iv: iv);

  return jsonEncode({
    'iv': base64Encode(iv.bytes),
    'data': encrypted.base64,
  });
}

//Decrypts an encrypted JSON string
static Future<String> decrypt(String encryptedJson) async {
  final key = await _getKey();
  final map = jsonDecode(encryptedJson);
  final iv = IV.fromBase64(map['iv']);
  final encrypted = Encrypted.fromBase64(map['data']);
  final encrypter = Encrypter(AES(key));
  return encrypter.decrypt(encrypted, iv: iv);
}

static Future<void> ensureKeyExists() async {
  final existingKey = await _secureStorage.read(key: _keyStorageKey);
  if (existingKey == null) {
    print("🔑 No encryption key found — generating one now...");
    await generateAndStoreKey();
  } else {
    print("✅ Encryption key already exists");
  }
}

}