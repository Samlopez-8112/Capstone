import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/crime_incident.dart';
import 'crime_data_source.dart';

// ChatGPT assisted in this alternative data source

class FixtureCrimeDataSource implements CrimeDataSource {
  final String path;
  FixtureCrimeDataSource({required this.path});

  bool _loaded = false;
  late List<CrimeIncident> _all;

  // read and parse json asset
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString(path);
    final dynamic json = jsonDecode(raw);

    final List list;
    // accept 3 json formats
    if (json is List) {
      list = json;
    } else if (json is Map && json['incidents'] is List) {
      list = json['incidents'];
    } else if (json is Map && json['data'] is List) {
      list = json['data'];
    } else {
      throw StateError('Unsupported fixture JSON format at $path');
    }

    _all = list.map<CrimeIncident>((e) => _toIncident(e)).toList();
    _loaded = true;
  }

  // Fetch incidents
  @override
  Future<List<CrimeIncident>> fetchIncidents({
    required LatLng center,
    required double radiusMeters,
    required int daysAgo,
  }) async {
    await _ensureLoaded(); // await json load

    // Bounding box approximation
    final bbox = _bboxFor(center, radiusMeters);
    // timeframe is now - (daysAgo)
    final cutoff = DateTime.now().toUtc().subtract(Duration(days: daysAgo));

    bool _inBox(LatLng p) {
      final inLat = p.latitude >= bbox['minLat']! && p.latitude <= bbox['maxLat']!;
      final minLng = bbox['minLng']!, maxLng = bbox['maxLng']!;
      final wrap = minLng > maxLng; // dateline wrap
      final inLng = wrap ? (p.longitude >= minLng || p.longitude <= maxLng)
                         : (p.longitude >= minLng && p.longitude <= maxLng);
      return inLat && inLng;
    }

    // distance between points, in meters
    double _distM(LatLng a, LatLng b) => _haversineMeters(a, b);

    // Filter results to those within the time window, bounding box, and precise radius
    final filtered = _all.where((c) {
      if (c.occurredAt.isBefore(cutoff)) return false;
      if (!_inBox(c.position)) return false;
      return _distM(center, c.position) <= radiusMeters;
    }).toList();

    // Sort by (distance asc, time desc)
    filtered.sort((a, b) {
      final da = _distM(center, a.position);
      final db = _distM(center, b.position);
      final byDist = da.compareTo(db);
      if (byDist != 0) return byDist;
      return b.occurredAt.compareTo(a.occurredAt);
    });

    // cap results to 200
    return filtered.take(200).toList();
  }

  // Parse json output into CrimeIncident object for use by code.
  CrimeIncident _toIncident(Map e) {
    num? _n(dynamic v) => (v is num) ? v : (v is String ? num.tryParse(v) : null);
    String? _s(dynamic v) => v?.toString();

    // convert labels to variables
    final lat = _n(e['incident_latitude'] ?? e['latitude'] ?? e['lat']);
    final lng = _n(e['incident_longitude'] ?? e['longitude'] ?? e['lng']);
    final when = _s(e['incident_date'] ?? e['datetime'] ?? e['date'] ?? e['occurred_at']);
    final offense = _s(e['incident_offense'] ?? e['offense'] ?? e['crime_type']) ?? 'Incident';
    final id = _s(e['incident_id'] ?? e['id']) ?? 'fix_${DateTime.now().microsecondsSinceEpoch}';
    final addr = _s(e['incident_address'] ?? e['address'] ?? e['block_address']);

    final dt = DateTime.tryParse(when ?? '')?.toUtc() ?? DateTime.now().toUtc();

    final pos = (lat != null && lng != null)
        ? LatLng(lat.toDouble(), lng.toDouble())
        : const LatLng(0, 0);

    return CrimeIncident(
      id: id,
      offense: offense,
      occurredAt: dt,
      position: pos,
      address: addr,
      source: 'fixture',
    );
  }

  // convert meters to coordinates
  Map<String, double> _bboxFor(LatLng c, double radiusM) {
    const R = 6371000.0;
    final dLat = (radiusM / R) * (180 / pi);
    final dLng = (radiusM / (R * cos(c.latitude * pi / 180))) * (180 / pi);

    double _wrap(double lon) {
      // normalize to [-180, 180]
      var x = lon;
      while (x > 180) x -= 360;
      while (x < -180) x += 360;
      return x;
    }

    return {
      'minLat': c.latitude - dLat,
      'maxLat': c.latitude + dLat,
      'minLng': _wrap(c.longitude - dLng),
      'maxLng': _wrap(c.longitude + dLng),
    };
  }

  // haversine formula gets precise distances between points on a sphere
  double _haversineMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * (pi / 180.0);
    final dLon = (b.longitude - a.longitude) * (pi / 180.0);
    final s1 = sin(dLat / 2), s2 = sin(dLon / 2);
    final t = s1 * s1 +
        cos(a.latitude * pi / 180.0) *
            cos(b.latitude * pi / 180.0) *
            s2 * s2;
    return R * 2 * asin(min(1.0, sqrt(t)));
  }
}
