import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:naguan_app/catalog/program.dart';
import 'package:naguan_app/catalog/program_summary.dart';
import 'package:naguan_app/catalog/session.dart';

/// Error al hablar con la API del catálogo. Implementar [Exception] (y no
/// [Error]) indica que es un fallo esperable, que la UI debe manejar: sin
/// red, backend caído, respuesta inesperada.
class CatalogException implements Exception {
  const CatalogException(this.message);

  final String message;

  @override
  String toString() => 'CatalogException: $message';
}

/// Cliente de la API del catálogo (programas y sesiones).
class CatalogClient {
  /// [accessToken] devuelve el token de acceso vigente (o null sin sesión).
  /// Es una función y no un String porque el token cambia: se renueva cada
  /// hora, y se lee recién al hacer cada request.
  ///
  /// [httpClient] es opcional: en la app se usa uno real; en los tests, un
  /// `MockClient`.
  ///
  /// `this._accessToken` inicializa el campo privado directamente; quien
  /// llama escribe `accessToken:` (sin el guion bajo).
  CatalogClient({
    required this.baseUrl,
    required this._accessToken,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String? Function() _accessToken;
  final http.Client _http;

  static const _timeout = Duration(seconds: 8);

  Future<List<ProgramSummary>> fetchPrograms() async {
    final json = await _getJson('/programs');
    if (json is! List) {
      throw const CatalogException('se esperaba una lista de programas');
    }
    return [
      for (final item in json)
        ProgramSummary.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<Program> fetchProgram(String slug) async {
    // Uri.encodeComponent escapa el slug por si trae caracteres especiales:
    // nunca concatenar datos crudos en una URL.
    final json = await _getJson('/programs/${Uri.encodeComponent(slug)}');
    return Program.fromJson(json as Map<String, dynamic>);
  }

  Future<Session> fetchSession(int id) async {
    final json = await _getJson('/sessions/$id');
    return Session.fromJson(json as Map<String, dynamic>);
  }

  /// Hace un GET y devuelve el cuerpo decodificado. Centraliza el manejo de
  /// errores para que cada método nuevo del cliente solo arme su modelo.
  Future<Object?> _getJson(String path) async {
    final http.Response response;
    try {
      final token = _accessToken();
      response = await _http
          .get(
            Uri.parse('$baseUrl$path'),
            // El token viaja en cada request: la API no guarda sesión
            // (stateless), solo valida la firma del token.
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          )
          .timeout(_timeout);
    } on Exception catch (e) {
      // Sin red, conexión rechazada, timeout...
      throw CatalogException('no se pudo conectar con el servidor ($e)');
    }

    if (response.statusCode == 401) {
      throw const CatalogException('sesión vencida o inválida');
    }
    if (response.statusCode != 200) {
      throw CatalogException('el servidor respondió ${response.statusCode}');
    }

    // Decodificamos los bytes como UTF-8 a mano. `response.body` usa el
    // charset del header Content-Type, y si no viene (como en nuestra API,
    // que manda "application/json" a secas) asume latin1: "Sesión" llegaría
    // como "SesiÃ³n". JSON siempre es UTF-8, así que esto es lo correcto.
    return jsonDecode(utf8.decode(response.bodyBytes));
  }
}
