
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

    // For each area, display circles with opacity based on crime severity rating
    int serial = 0;
    buckets.forEach((_, bucket) {
      final severityWeight = _weightedSeverity(bucket.crimes);
      final CrimeSeverity top = severityWeight.top;
      final double w = severityWeight.weight; // [0..1]

      final LatLng center = bucket.center;
      final double baseR = baseRadiusMeters * (1.0 + (top == CrimeSeverity.high ? 0.30 : top == CrimeSeverity.medium ? 0.15 : 0.0));

      // determine opacity of a circle using severity and associated value
      final double innerAlpha = switch (top) {
        CrimeSeverity.high   => opacityHigh * w,
        CrimeSeverity.medium => opacityMedium * w,
        CrimeSeverity.low    => opacityLow * w,
      };

      // build circle with cocentric fading rings
      for (int i = 0; i < layers; i++) {
        final double r = baseR * (1.0 + i * radiusStep);
        final double fade = math.pow(layerFalloff, i).toDouble();
        final int alpha = (255.0 * (innerAlpha * fade)).clamp(10.0, 255.0).toInt();

        final id = CircleId('$idPrefix${serial}_$i');
        out.add(Circle(
          circleId: id,
          center: center,
          radius: r,
          fillColor: Color.fromARGB(alpha, 255, 0, 0), // red shades
          strokeColor: Colors.transparent,
          strokeWidth: 0,
          zIndex: 1, // draws above map
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
