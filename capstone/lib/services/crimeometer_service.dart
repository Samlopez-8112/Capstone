import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Crimeometer service API call
// WIP - currently uses Crimeometer's public testing key,
// as we haven't received a key from the Crimeometer team

//Currently requests a list of crimes that have occured within a certain timeframe, in a radius around a given location.
// Testing has resulted in many calls with no data
// This is probably due to the limited data available on crimeometer's testing key.
class CrimeometerService {
  final String _baseUrl = 'https://api.crimeometer.com/v1/incidents/raw-data';

  // Provide coordinates and desired radius / timeframe to crimeometer api
  // default to 1 mile, 1 month. Feed coordinates on fetch call
  Future<Map<String, dynamic>> fetchCrimeData({
    required double latitude,
    required double longitude,
    double distanceMiles = 1.0,
    int daysAgo = 30,
  }) async {
    final apiKey = dotenv.env['CRIMEOMETER_API_KEY'] ?? ''; // grab API key from .env
    if (apiKey.isEmpty) {
      throw Exception('Crimeometer API key not found in .env'); 
    }

    final now = DateTime.now().toUtc();
    final start = now.subtract(Duration(days: daysAgo)); // grab date of 30 days ago

    final Uri uri = Uri.parse(_baseUrl).replace(queryParameters: { // parse input to send to api call
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'distance': '${distanceMiles}mi',
      'datetime_ini': start.toIso8601String(),
      'datetime_end': now.toIso8601String(), 
    });

    final response = await http.get( // http get protocol call
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
      },
    );

    if (response.statusCode == 200) { // if theres a response, return the requested data.
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch crime data: ${response.statusCode}'); // throw an error for a failed call
    }
  }
}
