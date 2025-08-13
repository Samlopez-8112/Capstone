import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/crime_incident.dart';
import 'crimeometer_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'crime_fixture_data_source.dart'; 


// CrimeDataSource mediates calls from 
//seperate data procurement methods. (API or Json)
abstract class CrimeDataSource {
  Future<List<CrimeIncident>> fetchIncidents({
    required LatLng center,
    required double radiusMeters,
    required int daysAgo,
  });

  static CrimeDataSource buildFromEnv() {
    final key = dotenv.env['CRIMEOMETER_API_KEY'] ?? '';
    final useFixture = (dotenv.env['CRIMEOMETER_USE_FIXTURE'] ?? '').toLowerCase() == 'true';
    final fixturePath = dotenv.env['CRIMEOMETER_FIXTURE'] ?? 'assets/crime_sample.json';

    if (useFixture || key.isEmpty) {
    return FixtureCrimeDataSource(path: fixturePath);
    }
    return CrimeometerAdapter(CrimeometerService());
  }
}

/// Crimeometer Call - Assistance from CHATGPT -
/// Would provide same output given proper Crimeometer key
class CrimeometerAdapter implements CrimeDataSource {
  final CrimeometerService _svc;
  CrimeometerAdapter(this._svc);

  @override
  Future<List<CrimeIncident>> fetchIncidents({
    required LatLng center,
    required double radiusMeters,
    required int daysAgo,
  }) async {
    final miles = radiusMeters / 1609.34;
    final json = await _svc.fetchCrimeData(
      latitude: center.latitude,
      longitude: center.longitude,
      distanceMiles: miles,
      daysAgo: daysAgo,
    );

    // Crimeometer commonly uses a top-level array like "incidents" or "data" (varies).
    final list = (json['incidents'] ?? json['data'] ?? []) as List;

    return list.map<CrimeIncident>((e) {
      final lat = (e['incident_latitude'] ?? e['latitude']) as num?;
      final lon = (e['incident_longitude'] ?? e['longitude']) as num?;
      final ts = (e['incident_date'] ?? e['datetime'])?.toString();

      return CrimeIncident(
        id: (e['incident_id'] ?? e['id'] ?? UniqueKey().toString()).toString(),
        offense: (e['incident_offense'] ?? e['offense'] ?? 'Incident').toString(),
        occurredAt: DateTime.tryParse(ts ?? '')?.toUtc() ?? DateTime.now().toUtc(),
        position: (lat != null && lon != null)
            ? LatLng(lat.toDouble(), lon.toDouble())
            : center,
        address: (e['incident_address'] ?? e['address'])?.toString(),
        source: 'crimeometer',
      );
    }).toList();
  }
}
