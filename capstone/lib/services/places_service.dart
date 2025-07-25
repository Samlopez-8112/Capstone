import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:capstone/models/poi_category.dart';

// Places access assisted by:
// https://levelup.gitconnected.com/flutter-google-maps-autocomplete-searchbar-with-debouncing-f5a215ee7381

// Suggestion class holds a placeID and the descption, (title of a place)
// More information can be gathered for future features
@immutable
class Suggestion {
  final String placeId;
  final String description;

  const Suggestion(this.placeId, this.description);
}

// Class for interaction with Places API
// more information can be gathered for future features
class PlaceApiProvider {
  final Client client = Client();

  // Session token groups requests together for billing
  // this should reduce API costs
  final String? sessionToken;

  /// API Key loaded from .env file
  static final String apiKey = dotenv.get('GOOGLE_MAPS_API_KEY', fallback: 'key_not_found');


  PlaceApiProvider(this.sessionToken);

  /// Fetch autocomplete suggestions
  Future<List<Suggestion>> fetchSuggestions(String input, String languageCode) async {
    if (input.isEmpty) return <Suggestion>[];

    final Uri requestUri = Uri.https('places.googleapis.com', 'v1/places:autocomplete');
    final headers = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
    };
    final body = jsonEncode({
      "input": input,
      "languageCode": languageCode,
      "sessionToken": sessionToken,
    });

    try {
      final response = await client.post(requestUri, headers: headers, body: body);
      if (response.statusCode == 200) { // if we get a response, place suggestions in the list
        return _parseSuggestions(response.body);
      } else {
        throw Exception('Failed to fetch suggestions: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Request failed: $e');
    }
  }

  /// Parses autocomplete JSON suggestions into a list
  List<Suggestion> _parseSuggestions(String responseBody) {
    final result = jsonDecode(responseBody);
    if (result['suggestions'] == null) return []; // no results = empty list
    return result['suggestions']
        .map<Suggestion>((json) => Suggestion(
              json['placePrediction']['placeId'] as String,
              json['placePrediction']['text']['text'] as String,
            ))
        .toList();
  }

  /// Retrieves latitude and longitude of a place (JSON), given google api's placeId
                                                                           /// Returns a LatLng object, which represents coordinates.
                                                                        
  Future<LatLng> getPlaceCoordinatesFromId(String placeId) async {
    final Uri requestUri = Uri.https(
      'places.googleapis.com',
      'v1/places/$placeId',
      {
        'key': apiKey,
        'fields': 'location',
        'sessionToken': sessionToken,
      },
    );

    try {
      final response = await client.get(requestUri);
      if (response.statusCode == 200) { // if we get a response, parse it to LatLng
        return _parseCoordinates(response.body);
      } else {
        throw Exception('Failed to load place coordinates: ${response.statusCode}'); // throw an error for api issue
      }
    } catch (e) {
      throw Exception('Request failed: $e'); //throw an error for failed request
    }
  }

  /// Parses coordinates from place detail response
  LatLng _parseCoordinates(String responseBody) {
    final result = jsonDecode(responseBody);
    if (result.containsKey('location') &&
        result['location'].containsKey('latitude') &&
        result['location'].containsKey('longitude')) {
      final latitude = result['location']['latitude'];
      final longitude = result['location']['longitude'];
      return LatLng(latitude, longitude);
    }
    return const LatLng(0, 0);
  }
}

/// ============== Nearby Places Section ==============

/// Fetches nearby points of interest based on category and radius
class NearbyPlacesService {
  final String apiKey = dotenv.get('GOOGLE_MAPS_API_KEY', fallback: 'key_not_found');

  Future<List<Map<String, dynamic>>> fetchNearby({
    required double latitude,
    required double longitude,
    required PoiCategory category,
    int radius = 1500,
  }) async {
    final type = category.apiValue;

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=$latitude,$longitude'
      '&radius=$radius'
      '&type=$type'
      '&key=$apiKey',
    );

    final response = await get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['results']);
    } else {
      throw Exception('Nearby search failed with ${response.statusCode}');
    }
  }
}
