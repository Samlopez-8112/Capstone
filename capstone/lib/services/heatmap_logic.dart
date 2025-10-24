import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HeatmapManager {
  final Set<Circle> _heatCircles = {};
  final Map<CircleId, Map<String, dynamic>> _circleMeta = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ratingsSub;
  Timer? _boundsDebounce;
  bool showHeatmap = true;

  Set<Circle> get circles => _heatCircles;
  Map<CircleId, Map<String, dynamic>> get circleMeta => _circleMeta;

  void dispose() {
    _boundsDebounce?.cancel();
    _ratingsSub?.cancel();
  }

  /// Debounced refresh
  void scheduleBoundsRefresh(
      Future<GoogleMapController> controllerFuture, VoidCallback onUpdate) {
    _boundsDebounce?.cancel();
    _boundsDebounce = Timer(const Duration(milliseconds: 250), () {
      refreshHeatForViewport(controllerFuture, onUpdate);
    });
  }

  /// Firestore listener per viewport
  Future<void> refreshHeatForViewport(
      Future<GoogleMapController> controllerFuture, VoidCallback onUpdate) async {
    if (!showHeatmap) return;
    final controller = await controllerFuture;

    LatLngBounds bounds;
    try {
      bounds = await controller.getVisibleRegion();
    } catch (_) {
      return;
    }

    final north = max(bounds.northeast.latitude, bounds.southwest.latitude);
    final south = min(bounds.northeast.latitude, bounds.southwest.latitude);
    final east = max(bounds.northeast.longitude, bounds.southwest.longitude);
    final west = min(bounds.northeast.longitude, bounds.southwest.longitude);

    _ratingsSub?.cancel();
    _ratingsSub = FirebaseFirestore.instance
        .collectionGroup('ratings')
        .where('center.lat', isGreaterThanOrEqualTo: south)
        .where('center.lat', isLessThanOrEqualTo: north)
        .orderBy('center.lat')
        .limit(1500)
        .snapshots()
        .listen((snap) async {
      final now = DateTime.now();
      final Map<String, List<Map<String, dynamic>>> grouped = {};

      // Group ratings by lat,lng,radius
      for (final doc in snap.docs) {
        final d = doc.data();
        final userId = d['userId'];
        final lat = (d['center']?['lat'] as num?)?.toDouble();
        final lng = (d['center']?['lng'] as num?)?.toDouble();
        final rating = (d['rating'] as num?)?.toDouble();
        final radiusMi = (d['radiusMiles'] as num?)?.toDouble() ?? 0.5;
        final ts = (d['timestamp'] as Timestamp?)?.toDate();

        if (lat == null || lng == null || rating == null) continue;
        if (lng < west || lng > east) continue;

        int endorsementCount = 0;
        try{
          final endorsementSnap = await doc.reference.collection('endorsements').get();
          endorsementCount = endorsementSnap.size;
        } catch(_){}

        final key =
            "${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}:r=${radiusMi.toStringAsFixed(2)}";
        grouped.putIfAbsent(key, () => []).add({
          'rating': rating,
          'timestamp': ts,
          'reasons': d['reasons'],
          'detail': d['personalExperienceDetail'],
          'lat': lat,
          'lng': lng,
          'radius': radiusMi,
          'userId': userId,
          'endorsementCount': endorsementCount,
        });
      }

      final Set<Circle> circles = {};
      final Map<CircleId, Map<String, dynamic>> meta = {};

      for (final entry in grouped.entries) {
        final group = entry.value;

        final lat = group.first['lat'] as double;
        final lng = group.first['lng'] as double;
        final radiusMi = group.first['radius'] as double;

        // Average rating
        final avgRating = group
                .map((r) => r['rating'] as double)
                .reduce((a, b) => a + b) /
            group.length;

        // Latest timestamp
        final latest = group
            .map((r) => r['timestamp'] as DateTime?)
            .whereType<DateTime>()
            .fold<DateTime?>(null,
                (a, b) => a == null || b.isAfter(a) ? b : a);

        // Intensity decay by time
        const halfLifeDays = 60.0;
        final decay = latest == null
            ? 1.0
            : pow(0.5,
                    now.difference(latest).inHours / 24.0 / halfLifeDays)
                .toDouble();
        final base = (5.0 - avgRating).clamp(0.0, 4.0);
        final intensity = (base * decay) / 4.0;
        if (intensity <= 0.02) continue;

        // Circle kernel size
        final kernel =
            (radiusMi * 1609.34 * 0.25).clamp(80.0, 250.0);
        final idStr = entry.key;
        final id = CircleId(idStr);

        const int layers = 5;
        for (int i = 0; i < layers; i++) {
          final layerRadius = kernel * (1 + i * 0.15);
          final fadeFactor = pow(0.7, i);
          final layerId = CircleId('${id.value}-layer$i');

          circles.add(
            Circle(
              circleId: layerId,
              center: LatLng(lat, lng),
              radius: layerRadius,
              strokeWidth: 0,
              fillColor: _colorForIntensity(intensity * fadeFactor),
            ),
          );
        }

        // Collect all reasons and details
        final allReasons = group
            .expand((r) => (r['reasons'] as List?) ?? [])
            .toList();
        final detailList = group
            .map((r) => r['detail'])
            .whereType<String>()
            .toList();

        final userIds = group
          .map((r) => r['userId'] as String?)
          .whereType<String>()
          .toSet();

        final totalEndorsements = group
          .map((r) => r['endorsementCount'] as int? ?? 0)
          .fold(0,(a, b) => a + b);

        meta[id] = {
          'avgRating': avgRating,
          'reasons': allReasons,
          'personalExperiences': detailList,
          'count': group.length,
          'radiusMiles': radiusMi,
          'center': {'lat': lat, 'lng': lng},
          'timestamp': latest,
          'userIds': userIds?.toList() ?? [],
          'endorsements': totalEndorsements,
        };
      }

      _heatCircles
        ..clear()
        ..addAll(circles);
      _circleMeta
        ..clear()
        ..addAll(meta);

      onUpdate();
    });
  }

  /// Handle tap on map → aggregate overlapping clusters
  void handleMapTap(BuildContext context, LatLng pos) {
    if (!showHeatmap || _heatCircles.isEmpty) return;

    final matches = _heatCircles.where((c) {
      final d = _calculateDistanceMeters(
          pos, c.center.latitude, c.center.longitude);
      return d <= c.radius;
    }).toList();

    if (matches.isEmpty) return;

    // Collect base IDs (strip "-layerX")
    final baseIds = matches
        .map((c) => c.circleId.value.contains('-layer')
            ? c.circleId.value.split('-layer').first
            : c.circleId.value)
        .toSet();

    // Gather all data for these base IDs
    final selectedData = baseIds
        .map((id) => _circleMeta[CircleId(id)])
        .whereType<Map<String, dynamic>>()
        .toList();

    if (selectedData.isEmpty) return;

    // Merge them into one summary
    final avgRating = selectedData
            .map((d) => d['avgRating'] as double? ?? 0.0)
            .reduce((a, b) => a + b) /
        selectedData.length;

    final totalCount = selectedData
        .map((d) => d['count'] as int? ?? 0)
        .reduce((a, b) => a + b);

    final allReasons =
        selectedData.expand((d) => d['reasons'] as List).toList();
    final allExperiences =
        selectedData.expand((d) => d['personalExperiences'] as List).toList();

    // Latest update across all
    final latest = selectedData
        .map((d) => d['timestamp'] as DateTime?)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

    _showRatingDetailsSheet(
      context,
      avgRating: avgRating,
      count: totalCount,
      reasons: allReasons,
      experiences: allExperiences,
      timestamp: latest,
      center: selectedData.first['center'],
      radius: selectedData.first['radiusMiles'],
      userIds: selectedData.expand((d) => d['userIds'] as List).toList(), 
      endorsements: selectedData
        .map((d) => d['endorsements'] as int? ?? 0)
        .fold(0,(a, b) => a + b),

    );
  }

  /// Bottom sheet with aggregated community rating
  void _showRatingDetailsSheet(
    BuildContext context, {
    required double avgRating,
    required int count,
    required List reasons,
    required List experiences,
    required DateTime? timestamp,
    required Map center,
    required double radius,
    required List userIds,
    required int endorsements,
  }) {
    // Aggregate reasons with counts
    final reasonCounts = <String, int>{};
    for (final r in reasons) {
      reasonCounts[r.toString()] = (reasonCounts[r.toString()] ?? 0) + 1;
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.shield_outlined),
                const SizedBox(width: 8),
                Text('Community rating',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Row(children: [
                  const Icon(Icons.star, size: 18, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(avgRating.toStringAsFixed(1)),
                ]),
              ]),
              Text('$count ratings submitted',
                  style: Theme.of(context).textTheme.bodySmall),
                Text('$endorsements Watchers',
                  style: Theme.of(context).textTheme.bodySmall),
              if (timestamp != null)
                Text('Updated: ${timestamp.toLocal()}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600])),
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Watch this area'),
                  onPressed: () async {
                    final userId = FirebaseAuth.instance.currentUser?.uid;
                    if (userId != null && center['lat'] != null && center['lng'] != null) {
                    for (final creatorId in userIds) {
                      final docPath = 
                        'crowdRatings/${center['lat'].toStringAsFixed(5)},${center['lng'].toStringAsFixed(5)}:r=${radius.toStringAsFixed(2)}mi/ratings/$creatorId';
                        await endorseRating(docPath, userId);
                    }
                    if (context.mounted){
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Thanks for your endorsement!')),
                        );
                    }
                  }
                },
              ),
            ),

              const SizedBox(height: 12),
              Text('Reasons', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              if (reasonCounts.isEmpty)
                const Text('No reasons provided')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasonCounts.entries
                      .map((e) => Chip(label: Text('${e.key} (${e.value})')))
                      .toList(),
                ),

              if (experiences.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Personal experiences',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                ...experiences.map((e) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(e.toString()),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Utilities
  double _calculateDistanceMeters(LatLng from, double lat2, double lng2) {
    const R = 6371000;
    final dLat = (lat2 - from.latitude) * (pi / 180);
    final dLng = (lng2 - from.longitude) * (pi / 180);
    final a = 0.5 -
        cos(dLat) / 2 +
        cos(from.latitude * pi / 180) *
            cos(lat2 * pi / 180) *
            (1 - cos(dLng)) / 2;
    return R * 2 * asin(sqrt(a));
  }

  Color _colorForIntensity(double t) {
    t = t.clamp(0.0, 1.0);
    Color lerp(Color a, Color b, double x) =>
        Color.lerp(a, b, x.clamp(0, 1))!;

    final Color col = t < 0.5
        ? lerp(Colors.green.shade400,
            Colors.yellow.shade600, t / 0.5)
        : lerp(Colors.yellow.shade600,
            Colors.red.shade800, (t - 0.5) / 0.5);

    final alpha = (40 + (t * 120)).round();
    return col.withAlpha(alpha);
  }

  Future<void> endorseRating(String ratingDocPath, String endorserUid) async {
  final docRef = FirebaseFirestore.instance.doc(ratingDocPath);
  final endorsementRef = docRef.collection('endorsements').doc(endorserUid);

  try {
    await FirebaseFirestore.instance.runTransaction((tx) async {
      // Read endorsement first
      final snap = await tx.get(endorsementRef);
      if (snap.exists) {
        print("Already endorsed by $endorserUid");
        return;
      }

      // Read rating document before any writes
      final ratingSnap = await tx.get(docRef);
      final currentCount = (ratingSnap.data()?['endorsementCount'] ?? 0) as int;

      // Now safe to write
      tx.set(endorsementRef, {
        'userId': endorserUid,
        'timestamp': FieldValue.serverTimestamp(),
      });

      tx.update(docRef, {'endorsementCount': currentCount + 1});
    });

    print("Endorsement saved successfully for $endorserUid");
  } catch (e) {
    print("Error endorsing rating: $e");
  }
}


}