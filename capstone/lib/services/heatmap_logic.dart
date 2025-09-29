import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
  
  //Devounced refresh
  void scheduleBoundsRefresh(Future<GoogleMapController> controllerFuture, VoidCallback onUpdate) {
    _boundsDebounce?.cancel();
    _boundsDebounce = Timer(const Duration(milliseconds: 250), () {
      refreshHeatForViewport(controllerFuture, onUpdate);
    });
  }

  //Firestore listener per viewpoint
  Future<void> refreshHeatForViewport(Future<GoogleMapController> controllerFuture, VoidCallback onUpdate) async {
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
        .listen((snap) {
      final now = DateTime.now();
      final Set<Circle> circles = {};
      final Map<CircleId, Map<String, dynamic>> meta = {};

      for (final doc in snap.docs) {
        final d = doc.data();
        final lat = (d['center']?['lat'] as num?)?.toDouble();
        final lng = (d['center']?['lng'] as num?)?.toDouble();
        final rating = (d['rating'] as num?)?.toDouble();
        final radiusMi = (d['radiusMiles'] as num?)?.toDouble() ?? 0.5;
        final ts = (d['timestamp'] as Timestamp?)?.toDate();

        if (lat == null || lng == null || rating == null) continue;
        if (lng < west || lng > east) continue;

        // intensity calc
        final base = (5.0 - rating).clamp(0.0, 4.0);
        final ageDays = ts == null ? 0.0 : now.difference(ts).inHours / 24.0;
        const halfLifeDays = 60.0;
        final decay = pow(0.5, ageDays / halfLifeDays).toDouble();
        final intensity = (base * decay) / 4.0;
        if (intensity <= 0.02) continue;

        final kernel = (radiusMi * 1609.34 * 0.25).clamp(80.0, 250.0);
        final id = CircleId('${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}_${doc.id}');

        const int layers = 5;
        for(int i = 0; i < layers; i++){
          final layerRadius = kernel * (1 + i * 0.15);
          final fadeFactor = pow(0.7, i);
          final layerId = CircleId('$id-layer$i');

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

        meta[id] = {
          'rating': rating,
          'reasons': d['reasons'],
          'personalExperienceDetail': d['personalExperienceDetail'],
          'timestamp': ts,
          'radiusMiles': radiusMi,
          'center': {'lat': lat, 'lng': lng},
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

  // Handle tap on map, check if inside a circle
  void handleMapTap(BuildContext context, LatLng pos) {
    if (!showHeatmap || _heatCircles.isEmpty) return;

    final matches = _heatCircles.where((c) {
      final d = _calculateDistanceMeters(
          pos, c.center.latitude, c.center.longitude);
      return d <= c.radius;
    }).toList();

    if (matches.isEmpty) return;

    matches.sort((a, b) {
      final da = _calculateDistanceMeters(
          pos, a.center.latitude, a.center.longitude);
      final db = _calculateDistanceMeters(
          pos, b.center.latitude, b.center.longitude);
      return da.compareTo(db);
    });

    final CircleId id = matches.first.circleId;
    final data = _circleMeta[id];
    if (data != null) _showRatingDetailsSheet(context, data);
  }

  // Show bottom sheet with rating details
  void _showRatingDetailsSheet(BuildContext context, Map<String, dynamic> d) {
    final List reasons = (d['reasons'] as List?) ?? const [];
    final String? detail = (d['personalExperienceDetail'] as String?)?.trim();
    final double? rating = (d['rating'] as num?)?.toDouble();
    final double? radiusMi = (d['radiusMiles'] as num?)?.toDouble();
    final DateTime? ts = d['timestamp'] is Timestamp
        ? (d['timestamp'] as Timestamp).toDate()
        : d['timestamp'] as DateTime?;

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
                if (rating != null)
                  Row(children: [
                    const Icon(Icons.star, size: 18, color: Colors.amber),
                    const SizedBox(width: 4),
                    Text(rating.toStringAsFixed(1)),
                  ]),
              ]),
              const SizedBox(height: 8),
              if (radiusMi != null)
                Text('Reported radius: ${radiusMi.toStringAsFixed(2)} mi',
                    style: Theme.of(context).textTheme.bodySmall),
              if (ts != null)
                Text('Updated: ${ts.toLocal()}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey[600])),

              const SizedBox(height: 12),
              Text('Reasons', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              if (reasons.isEmpty)
                const Text('No reasons provided')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasons
                      .map<Widget>((r) => Chip(label: Text(r.toString())))
                      .toList(),
                ),

              if (detail != null && detail.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Personal experience',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(detail),
                ),
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
        ? lerp(Colors.green.shade400, Colors.yellow.shade600, t / 0.5)
        : lerp(Colors.yellow.shade600, Colors.red.shade800, (t - 0.5) / 0.5);

    final alpha = (40 + (t * 120)).round();
    return col.withAlpha(alpha);
  }
}
