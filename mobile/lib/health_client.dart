import 'dart:convert';

import 'package:http/http.dart' as http;

class HealthClient {
  /// [httpClient] es opcional: en la app se usa uno real; en los tests se
  /// pasa un `MockClient` para no salir a la red.
  HealthClient({required this.baseUrl, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  Future<String> fetchStatus() async {
    final response = await _http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      throw Exception('El backend respondió ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['status'] as String;
  }
}
