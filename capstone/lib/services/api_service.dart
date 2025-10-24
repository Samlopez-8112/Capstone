import 'dart:convert';
import 'package:http/http.dart' as http;

/// API base URL — need to change this if we redeploy
const String baseUrl = "https://api-zkckvg7x7a-uc.a.run.app";

/// Centralized API Service for SafeRoute
class ApiService {
  // Generic GET request
  static Future<dynamic> _getRequest(String endpoint,
      {Map<String, String>? params}) async {
    try {
      final uri =
          Uri.parse("$baseUrl$endpoint").replace(queryParameters: params);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        throw Exception(
            "Failed GET ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      print("❌ GET $endpoint error: $e");
      rethrow;
    }
  }

  // Generic POST request
  static Future<dynamic> _postRequest(
      String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse("$baseUrl$endpoint");
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: json.encode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception(
            "Failed POST ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      print("❌ POST $endpoint error: $e");
      rethrow;
    }
  }

  // --- Safe Routes ---
  static Future<List<dynamic>> fetchSafeRoutes() async {
    final data = await _getRequest("/safe-routes");
    return data["data"] ?? [];
  }

  // --- Construction Zones ---
  static Future<List<dynamic>> fetchConstructionZones() async {
    final data = await _getRequest("/construction");
    return data["data"] ?? [];
  }

  // --- Crime Zones ---
  static Future<List<dynamic>> fetchCrimeZones(
      {double? lat, double? lng}) async {
    final params = (lat != null && lng != null)
        ? {
            "lat": lat.toString(),
            "lng": lng.toString(),
          }
        : null;
    final data = await _getRequest("/crime-zones", params: params);
    return data["data"] ?? [];
  }

  // --- Reviews ---
  static Future<List<dynamic>> fetchReviews() async {
    final data = await _getRequest("/reviews");
    return data["data"] ?? [];
  }

  static Future<Map<String, dynamic>> postReview({
    required String userId,
    required double rating,
    required String comment,
  }) async {
    final body = {
      "userId": userId,
      "rating": rating,
      "comment": comment,
    };
    final data = await _postRequest("/reviews", body);
    return data;
  }
}
// --- Additional API methods can be added here ---