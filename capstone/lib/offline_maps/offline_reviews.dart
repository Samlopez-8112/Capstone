// lib/offline_maps/offline_reviews.dart
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

class OfflineReviews {
  late File _file;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/offline/reviews.json');
    if (!await _file.exists()) {
      await _file.writeAsString(jsonEncode({'reviews': []}));
    }
  }

  Future<List<Map<String, dynamic>>> _loadAll() async {
    final txt = await _file.readAsString();
    final data = jsonDecode(txt);
    return (data['reviews'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> _saveAll(List<Map<String, dynamic>> reviews) async {
    await _file.writeAsString(jsonEncode({'reviews': reviews}));
  }

  Future<List<Map<String, dynamic>>> getReviews(String poiId) async {
    final all = await _loadAll();
    return all.where((r) => r['poiId'] == poiId).toList();
  }

  Future<void> addReview({
    required String poiId,
    required String user,
    required double rating,
    required String comment,
  }) async {
    final reviews = await _loadAll();
    reviews.add({
      'poiId': poiId,
      'user': user,
      'rating': rating,
      'comment': comment,
      'date': DateTime.now().toIso8601String(),
      'pendingSync': true,
    });
    await _saveAll(reviews);
  }

  Future<void> syncPendingReviews() async {
    final all = await _loadAll();
    final synced = <Map<String, dynamic>>[];

    for (final r in all) {
      if (r['pendingSync'] == true) {
        try {
          await _firestore
              .collection('reviews')
              .doc(r['poiId'])
              .collection('entries')
              .add({
            'user': r['user'],
            'rating': r['rating'],
            'comment': r['comment'],
            'date': r['date'],
          });
          r['pendingSync'] = false;
        } catch (_) {}
      }
      synced.add(r);
    }

    await _saveAll(synced);
  }
}
