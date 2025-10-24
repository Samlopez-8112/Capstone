
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/crime_incident.dart';
import '../models/crime_severity.dart'; // contains classifySeverity(...) and CrimeSeverity enum
import '../utils/crimefilter.dart';     // contains categoriesForOffense(...), CrimeCategory


// Heatmap class, 
class CrimeHeatmap {
  
  // Visual factors of crimemap circles 
  final int layers;
  final double baseRadiusMeters;
  final double radiusStep;     // multiplier per layer (0.20 = 20% increase)
  final double opacityHigh;    // different severities create different opacity circles
  final double opacityMedium;  
  final double opacityLow;     
  final double layerFalloff;   // opacity fade per layer
  final bool clipToViewport;   // if true, drops crimes outside the provided bounds
  final int minMediumClusterCount;      // how many medium incidents needed nearby
  final double clusterOverlapFraction;  // ~0.5 => require ~50% overlap


  // values for crime instance circles
  CrimeHeatmap({
    this.layers = 5,
    this.baseRadiusMeters = 160.0,
    this.radiusStep = 0.22,
    this.opacityHigh = 0.32,
    this.opacityMedium = 0.16,
    this.opacityLow = 0.08,
    this.layerFalloff = 0.70,
    this.clipToViewport = true,
    this.minMediumClusterCount = 3,
    this.clusterOverlapFraction = 0.5
  });

  /// Build circles from crime list
  Set<Circle> build({
    required List<CrimeIncident> crimes,
    Set<CrimeCategory>? activeFilters,
    LatLngBounds? viewport,
    String idPrefix = 'heat_',
  }) {
    final out = <Circle>{};
    if (crimes.isEmpty) return out;

    // "Bucket" logic refers to preventing visual issues with circles at the same coordinate.
    final Map<String, _Bucket> buckets = {};
    for (final c in crimes) {
      final pos = c.position;
      if (clipToViewport && viewport != null && !_contains(viewport, pos)) {
        continue;
      }
      // Filter by current selected filters 
      if (activeFilters != null && activeFilters.isNotEmpty) {
        final cats = categoriesForOffense(c.offense);
        final matched = cats.any(activeFilters.contains);
        if (!matched) continue;
      }
      final bucketKey = _bucketKey(pos.latitude, pos.longitude, sizeMeters: 25.0);
      buckets.putIfAbsent(bucketKey, () => _Bucket(pos)).add(c);
    }

  // For each area, display circles with rules:
// - High: always
// - Medium: only if clustered strongly
// - Low: never
int serial = 0;

// Precompute medium incident positions for quick neighborhood checks
final List<LatLng> mediumPositions = [];
buckets.forEach((_, b) {
  for (final c in b.crimes) {
    final s = classifySeverity(c.offense);
    if (s == CrimeSeverity.medium) mediumPositions.add(c.position);
  }
});

buckets.forEach((_, bucket) {
  final severityWeight = _weightedSeverity(bucket.crimes);
  final CrimeSeverity top = severityWeight.top;
  final double w = severityWeight.weight;

  // Base radius is already severity-aware in your code
  final LatLng center = bucket.center;
  final double baseR = baseRadiusMeters *
      (1.0 + (top == CrimeSeverity.high ? 0.30 : top == CrimeSeverity.medium ? 0.15 : 0.0));

  // ----- NEW: decide whether to draw based on severity -----
  bool shouldDraw = false;
  if (top == CrimeSeverity.high) {
    // High → always show
    shouldDraw = true;
  } else if (top == CrimeSeverity.medium) {
    shouldDraw = true; // temporarily, always show medium markers
    // Medium → require a local cluster so the circles would overlap >= ~50%
    // Approximate by counting medium incidents within (clusterOverlapFraction * baseR)
    final double neighborhoodMeters = clusterOverlapFraction * baseR;

    int nearbyMediums = 0;
    // quick degrees-per-meter at this latitude
    final double dLatPerM = 1 / 111000.0;
    final double dLonPerM = 1 / (111000.0 * math.cos(center.latitude * math.pi / 180));

    final double latWin = neighborhoodMeters * dLatPerM;
    final double lonWin = neighborhoodMeters * dLonPerM;

    for (final p in mediumPositions) {
      // fast AABB prune, then precise distance (approx.)
      if ((p.latitude - center.latitude).abs() <= latWin &&
          (p.longitude - center.longitude).abs() <= lonWin) {
        final double dMeters = _haversineMeters(center, p);
        if (dMeters <= neighborhoodMeters) nearbyMediums++;
      }
      if (nearbyMediums >= minMediumClusterCount) {
        shouldDraw = true;
        break;
      }
    }
  } else {
    // Low → never show
    shouldDraw = false;
  }

  if (!shouldDraw) {
    return; // skip drawing this bucket
  }
  // ---------------------------------------

  // determine opacity of a circle using severity and associated value (your code)
  final double innerAlpha = switch (top) {
    CrimeSeverity.high   => opacityHigh * w,
    CrimeSeverity.medium => opacityMedium * w,
    CrimeSeverity.low    => opacityLow * w,
  };

  // build circle with concentric fading rings (your code)
  for (int i = 0; i < layers; i++) {
    final double r = baseR * (1.0 + i * radiusStep);
    final double fade = math.pow(layerFalloff, i).toDouble();
    final int alpha = (255.0 * (innerAlpha * fade)).clamp(10.0, 255.0).toInt();

    final id = CircleId('$idPrefix${serial}_$i');
    out.add(Circle(
      circleId: id,
      center: center,
      radius: r,
      fillColor: Color.fromARGB(alpha, 255, 0, 0),
      strokeColor: Colors.transparent,
      strokeWidth: 0,
      zIndex: 1,
    ));
  }

  serial++;
});


    return out;
  }

  /// Quick "contains" that accounts for crossing the antimeridian in LatLngBounds.
  bool _contains(LatLngBounds b, LatLng p) {
    final inLat = (p.latitude >= b.southwest.latitude && p.latitude <= b.northeast.latitude) ||
                  (p.latitude >= b.northeast.latitude && p.latitude <= b.southwest.latitude); // handle inverted if any

    bool inLon;
    if (b.southwest.longitude <= b.northeast.longitude) {
      // normal case
      inLon = p.longitude >= b.southwest.longitude && p.longitude <= b.northeast.longitude;
    } else {
      // bounds cross the antimeridian
      inLon = p.longitude >= b.southwest.longitude || p.longitude <= b.northeast.longitude;
    }
    return inLat && inLon;
  }
}

  //severity statistics for a bucket
  class _Bucket {
    final LatLng center;
    final List<CrimeIncident> crimes = [];
    _Bucket(this.center);
    void add(CrimeIncident c) => crimes.add(c);
  }

  class _SeverityStat {
    final CrimeSeverity top;
    final double weight; // 0..1
    _SeverityStat(this.top, this.weight);
  }

  _SeverityStat _weightedSeverity(List<CrimeIncident> crimes) {
    if (crimes.isEmpty) return _SeverityStat(CrimeSeverity.low, 0.0);

    double hi = 0, md = 0, lo = 0;
    for (final c in crimes) {
      final s = classifySeverity(c.offense);
      switch (s) {
        case CrimeSeverity.high:   hi += 1.0; break;
        case CrimeSeverity.medium: md += 1.0; break;
        case CrimeSeverity.low:    lo += 1.0; break;
      }
    }

    // Normalize counts to [0..1], compute the highest severity & relative weight
    final total = (hi + md + lo).clamp(1.0, double.infinity);
    final maxVal = math.max(hi, math.max(md, lo));
    final top = (maxVal == hi) ? CrimeSeverity.high : (maxVal == md) ? CrimeSeverity.medium : CrimeSeverity.low;
    final weight = (maxVal / total).clamp(0.0, 1.0);
    return _SeverityStat(top, weight);
  }

  String _bucketKey(double lat, double lon, {double sizeMeters = 25.0}) {
    // Approx degrees per meter at this latitude
    final double dLat = sizeMeters / 111000.0;
    final double dLon = sizeMeters / 111000.0;
    final int iLat = (lat / dLat).round();
    final int iLon = (lon / dLon).round();
    return '$iLat:$iLon';
  }

  double _haversineMeters(LatLng a, LatLng b) {
  const R = 6371000.0; // meters
  final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
  final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
  final la1 = a.latitude * math.pi / 180.0;
  final la2 = b.latitude * math.pi / 180.0;
  final h = math.sin(dLat/2) * math.sin(dLat/2) +
            math.cos(la1) * math.cos(la2) *
            math.sin(dLon/2) * math.sin(dLon/2);
  return 2 * R * math.asin(math.sqrt(h));
}

