import 'package:cloud_firestore/cloud_firestore.dart';

/// A service class to interact with Firestore for construction zones.
/// This fetches zones that are currently active based on start/end dates
/// and the `active` flag in Firestore.
class ConstructionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Stream of all active construction zones.
  /// Zones are considered active if:
  /// - `active` is true
  /// - `startDate` <= now
  /// - `endDate` >= now
  Stream<List<Map<String, dynamic>>> getActiveZones() {
    final now = DateTime.now();

    return _db.collection('construction_zones')
      .where('active', isEqualTo: true)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data();

          // Parse Firestore Timestamps into DateTime
          final start = (data['startDate'] as Timestamp?)?.toDate();
          final end = (data['endDate'] as Timestamp?)?.toDate();

          final isActive = (start == null || start.isBefore(now)) &&
                           (end == null || end.isAfter(now));

          return {
            'id': doc.id,
            'name': data['name'] ?? 'Unnamed Zone',
            'lat': (data['lat'] as num?)?.toDouble(),
            'lng': (data['lng'] as num?)?.toDouble(),
            'radius': data['radius'] ?? 100,
            'polygon': data['polygon'], // List<Map<String,double>>
            'startDate': start,
            'endDate': end,
            'active': isActive,
          };
        }).where((z) => z['active'] == true).toList();
      });
  }
}
