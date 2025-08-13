import 'package:google_maps_flutter/google_maps_flutter.dart';

// object model for crime incidents
// incidents are converted from JSON to an object of this type
class CrimeIncident {
  final String id;
  final String offense;
  final String? address;
  final DateTime occurredAt;
  final LatLng position;
  final String source; // actual API or mock

  CrimeIncident({
    required this.id,
    required this.offense,
    required this.occurredAt,
    required this.position,
    this.address,
    this.source = 'mock', // set default source to mock sources
  });
}
