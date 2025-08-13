import 'package:google_maps_flutter/google_maps_flutter.dart';

// Crime severity classifier

//crimes can be low, medium, or high seveirty
enum CrimeSeverity { low, medium, high }

// set hues as wanted, currently Red for high, orange for med, green for low.
extension CrimeSeverityX on CrimeSeverity {
  double get hue => switch (this) {
    CrimeSeverity.high   => BitmapDescriptor.hueRed,
    CrimeSeverity.medium => BitmapDescriptor.hueOrange,
    CrimeSeverity.low    => BitmapDescriptor.hueGreen,
  };
  String get label => switch (this) {
    CrimeSeverity.high   => 'High',
    CrimeSeverity.medium => 'Medium',
    CrimeSeverity.low    => 'Low',
  };
}

// read the given offense, if it contains one of these phrases, set the severity to the cooresponding level
CrimeSeverity classifySeverity(String offense) {
  final o = offense.toLowerCase();
  if (o.contains('assault') || o.contains('robbery') || o.contains('homicide') ||
      o.contains('murder') || o.contains('shoot') || o.contains('weapon') ||
      o.contains('dui') || o.contains('dwi') || o.contains('arson')) {
    return CrimeSeverity.high;
  }
  if (o.contains('burglary') || o.contains('vehicle') || o.contains('auto') ||
      o.contains('motor') || o.contains('drug') || o.contains('theft') ||
      o.contains('narcotic') || o.contains('battery')) {
    return CrimeSeverity.medium;
  }
  return CrimeSeverity.low;
}
