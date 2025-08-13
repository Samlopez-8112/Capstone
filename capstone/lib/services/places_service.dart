import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:capstone/models/poi_category.dart';

// Places access assisted by:
// https://levelup.gitconnected.com/flutter-google-maps-autocomplete-searchbar-with-debouncing-f5a215ee7381

// Suggestion class holds a placeID and the description, (title of a place)
// More information can be gathered for future features
@immutable
class Suggestion {
  final String placeId;
  final String description;

  const Suggestion(this.placeId, this.description);
}

// Class for interaction with Places API
// More information can be gathered for future features
class PlaceApiProvider {
  final Client client = Client();

  /// API Key loaded from .env file
  static final String apiKey = dotenv.get('GOOGLE_MAPS_API_KEY', fallback: 'key_not_found');

  // Constructor updated to no longer require sessionToken
  PlaceApiProvider();

  /// Fetch autocomplete suggestions from Places API
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

  /// Retrieves latitude and longitude of a place (JSON), given Google API's placeId
  /// Returns a LatLng object, which represents coordinates.
  Future<LatLng> getPlaceCoordinatesFromId(String placeId) async {
    final Uri requestUri = Uri.https(
      'places.googleapis.com',
      'v1/places/$placeId',
      {
        'key': apiKey,
        'fields': 'location',
      },
    );

    try {
      final response = await client.get(requestUri);
      if (response.statusCode == 200) { // if we get a response, parse it to LatLng
        return _parseCoordinates(response.body);
      } else {
        throw Exception('Failed to load place coordinates: ${response.statusCode}'); // throw an error for API issue
      }
    } catch (e) {
      throw Exception('Request failed: $e'); // throw an error for failed request
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
    return const LatLng(0, 0); // Return default LatLng if no location is found
  }

  /// Fetches detailed information for a place (e.g., phone number, website, rating)
  Future<Map<String, dynamic>> fetchPlaceDetails(String placeId) async {
    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'name,formatted_address,formatted_phone_number,website,rating,photos,geometry',
        'key': apiKey,
      },
    );

    try {
      final response = await client.get(url);
      if (response.statusCode == 200) {
        return _parsePlaceDetails(response.body);
      } else {
        throw Exception('Failed to fetch place details: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Request failed: $e');
    }
  }

  /// Parses place details from the response body
  Map<String, dynamic> _parsePlaceDetails(String responseBody) {
    final result = jsonDecode(responseBody);
    if (result['status'] == 'OK' && result['result'] != null) {
      return result['result'];
    } else {
      throw Exception('Failed to retrieve place details');
    }
  }

  // Method version of finding place nearest - necessary to display info on precise locations
  Future<Map<String, dynamic>?> fetchNearestPlaceBasic(
    LatLng pos, {
    int radius = 80, // meters
  }) async {
    final url = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/nearbysearch/json',
      {
        'location': '${pos.latitude},${pos.longitude}',
        'radius': radius.toString(),
        'key': apiKey,
      },
    );

    final resp = await client.get(url);
    if (resp.statusCode != 200) {
      throw Exception('Nearest place lookup failed: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (data['results'] as List?) ?? const [];
    if (results.isEmpty) return null;
    return results.first as Map<String, dynamic>;
  }

  /// convert Latlng to place details
  Future<Map<String, dynamic>?> fetchDetailsForLatLng(
    LatLng pos, {
    int searchRadius = 80,
  }) async {
    final basic = await fetchNearestPlaceBasic(pos, radius: searchRadius);
    if (basic == null) return null;

    final placeId = basic['place_id'] as String?;
    if (placeId == null) return null;

    final details = await fetchPlaceDetails(placeId);

    // Enrich details with any fields Nearby has but Details might not:
    details['vicinity'] ??= basic['vicinity'];
    details['geometry'] ??= basic['geometry']; // Nearby includes geometry.location

    return details;
  }
 
 //find nearest 'business' establishment 
Future<Map<String, dynamic>?> fetchNearestEstablishmentDetails(LatLng pos) async {
  final nearby = Uri.https(
    'maps.googleapis.com',
    '/maps/api/place/nearbysearch/json',
    {
      'location': '${pos.latitude},${pos.longitude}',
      'rankby': 'distance',
      'type': 'establishment', // prefer businesses over localities
      'key': apiKey,
    },
  );

  final r = await client.get(nearby);
  if (r.statusCode != 200) {
    throw Exception('Nearby (establishment) failed: ${r.statusCode} ${r.body}');
  }
  final data = jsonDecode(r.body) as Map<String, dynamic>;
  final results = (data['results'] as List?) ?? const [];
  if (results.isEmpty) return null;

  final first = results.first as Map<String, dynamic>;
  final placeId = first['place_id'] as String?;
  if (placeId == null) return null;

  final details = await fetchPlaceDetails(placeId);
  // Attach geometry from nearby if details didn’t include it
  details['geometry'] ??= first['geometry'];
  return details;
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
