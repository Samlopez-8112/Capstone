import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class CrimeometerService {
  static const _baseUrl = 'https://api.crimeometer.com/v1/incidents/raw-data';

  /// Format like: 'YYYY-MM-DD HH:MM:SS' in UTC (matches common v1 examples)
  String _fmt(DateTime dtUtc) {
    final y = dtUtc.year.toString().padLeft(4, '0');
    final mo = dtUtc.month.toString().padLeft(2, '0');
    final d = dtUtc.day.toString().padLeft(2, '0');
    final h = dtUtc.hour.toString().padLeft(2, '0');
    final mi = dtUtc.minute.toString().padLeft(2, '0');
    final s = dtUtc.second.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi:$s';
  }

  Future<Map<String, dynamic>> fetchCrimeData({
    required double latitude,
    required double longitude,
    double distanceMiles = 1.0,
    int daysAgo = 30,
    int page = 1,            // basic paging
    int? pageSize,           // if your plan supports it
    int maxRetries = 2,      // retry a couple times on 429/5xx
  }) async {
    final apiKey = dotenv.env['CRIMEOMETER_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      throw Exception('Crimeometer API key not found in .env');
    }

    final nowUtc = DateTime.now().toUtc();
    final startUtc = nowUtc.subtract(Duration(days: daysAgo));

    final qp = <String, String>{
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'distance': '${distanceMiles}mi',
      'datetime_ini': _fmt(startUtc),
      'datetime_end': _fmt(nowUtc),
      'page': page.toString(),
      if (pageSize != null) 'max': pageSize.toString(), // some integrations use "max" or "page_size"
    };

    final uri = Uri.parse(_baseUrl).replace(queryParameters: qp);

    int attempt = 0;
    while (true) {
      attempt++;
      final resp = await http
          .get(uri, headers: {
            'Accept': 'application/json',
            'x-api-key': apiKey,
          })
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }

      // Backoff on 429 or transient 5xx
      if ((resp.statusCode == 429 || (resp.statusCode >= 500 && resp.statusCode < 600)) &&
          attempt <= maxRetries) {
        final waitMs = 800 * attempt; // simple backoff
        await Future.delayed(Duration(milliseconds: waitMs));
        continue;
      }

      // Bubble up richer error info
      final body = resp.body.isNotEmpty ? resp.body : '<empty>';
      throw HttpException(
        'Crimeometer error ${resp.statusCode}: $body',
        uri: uri,
      );
    }
  }
}
