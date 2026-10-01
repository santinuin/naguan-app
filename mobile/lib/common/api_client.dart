import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error al hablar con la API. Implementar [Exception] (y no [Error]) indica
/// que es un fallo esperable, que la UI debe manejar: sin red, backend caído,
/// respuesta inesperada.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// El status HTTP, si hubo respuesta (null si ni siquiera se conectó).
  final int? statusCode;

  @override
  String toString() => 'ApiException: $message';
}

/// Lo común a todos los clientes de la API: la URL base, el token en cada
/// request, los timeouts, el manejo de errores y la decodificación del JSON.
///
/// Los clientes de cada funcionalidad (CatalogClient, TrainingClient) lo
/// reciben por constructor y solo arman sus modelos: composición, no
/// herencia.
class ApiClient {
  /// [accessToken] devuelve el token de acceso vigente (o null sin sesión).
  /// Es una función y no un String porque el token cambia: se renueva cada
  /// hora, y se lee recién al hacer cada request.
  ///
  /// [httpClient] es opcional: en la app se usa uno real; en los tests, un
  /// `MockClient`.
  ///
  /// `this._accessToken` inicializa el campo privado directamente; quien
  /// llama escribe `accessToken:` (sin el guion bajo).
  ///
  /// [onUnauthorized] se llama ante un 401: el token ya no sirve (venció y
  /// no se pudo renovar, o la cuenta se borró). La app lo usa para cerrar la
  /// sesión, y AuthGate vuelve a mostrar el ingreso.
  ApiClient({
    required this.baseUrl,
    required this._accessToken,
    this.onUnauthorized,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String? Function() _accessToken;
  final void Function()? onUnauthorized;
  final http.Client _http;

  static const _timeout = Duration(seconds: 8);

  Future<Object?> getJson(String path) => _send('GET', path);

  Future<Object?> postJson(String path, Object body) =>
      _send('POST', path, body: body);

  Future<void> delete(String path) => _send('DELETE', path);

  /// Arma el request, lo manda y decodifica la respuesta. Centraliza el
  /// manejo de errores para que cada método de los clientes solo arme su
  /// modelo.
  Future<Object?> _send(String method, String path, {Object? body}) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'));
    final token = _accessToken();
    // El token viaja en cada request: la API no guarda sesión (stateless),
    // solo valida la firma del token.
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      // send devuelve la respuesta como stream; fromStream la junta entera.
      final streamed = await _http.send(request).timeout(_timeout);
      response = await http.Response.fromStream(streamed);
    } on Exception catch (e) {
      // Sin red, conexión rechazada, timeout...
      throw ApiException('no se pudo conectar con el servidor ($e)');
    }

    // Decodificamos los bytes como UTF-8 a mano. `response.body` usa el
    // charset del header Content-Type, y si no viene (como en nuestra API,
    // que manda "application/json" a secas) asume latin1: "Sesión" llegaría
    // como "SesiÃ³n". JSON siempre es UTF-8, así que esto es lo correcto.
    final text = utf8.decode(response.bodyBytes);
    final status = response.statusCode;

    if (status == 401) {
      // ?.call(): llama a la función solo si no es null.
      onUnauthorized?.call();
      throw const ApiException('sesión vencida o inválida', statusCode: 401);
    }
    if (status < 200 || status >= 300) {
      // La API manda {"error": "..."}: si viene, se usa ese mensaje.
      final message = switch (_tryDecode(text)) {
        {'error': String error} => error,
        _ => 'el servidor respondió $status',
      };
      throw ApiException(message, statusCode: status);
    }
    // 204 No Content: no hay cuerpo.
    return text.isEmpty ? null : jsonDecode(text);
  }

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
