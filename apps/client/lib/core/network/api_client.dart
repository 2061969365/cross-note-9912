import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class ApiClient {
  final String baseUrl;
  final http.Client _http;
  ApiClient({String? baseUrl, http.Client? httpClient}) : baseUrl = baseUrl ?? AppConfig.defaultServerUrl, _http = httpClient ?? http.Client();

  Future<Map<String, dynamic>> pull({String? since, int limit = 100}) async {
    final uri = Uri.parse('$baseUrl/api/sync/pull').replace(queryParameters: {
      if (since != null) 'since': since,
      'limit': '$limit',
      'includeDeleted': '1',
    });
    try {
      final r = await _http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('pull timed out after 10s', const Duration(seconds: 10)),
      );
      if (r.statusCode != 200) throw Exception('pull ${r.statusCode} ${r.body}');
      return jsonDecode(r.body) as Map<String, dynamic>;
    } on TimeoutException {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> push({required String entityType, required String operation, required Map<String, dynamic> entity}) async {
    final uri = Uri.parse('$baseUrl/api/sync/push');
    try {
      final r = await _http
          .post(uri, headers: {'content-type': 'application/json'}, body: jsonEncode({'entityType': entityType, 'operation': operation, 'entity': entity}))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('push timed out after 10s', const Duration(seconds: 10)),
          );
      if (r.statusCode != 200 && r.statusCode != 201) throw Exception('push ${r.statusCode} ${r.body}');
      return jsonDecode(r.body) as Map<String, dynamic>;
    } on TimeoutException {
      rethrow;
    }
  }
}
