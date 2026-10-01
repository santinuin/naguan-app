import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/program_summary.dart';

CatalogClient clientReturning(http.Response response) {
  return CatalogClient(
    baseUrl: 'http://backend.test',
    accessToken: () => 'token-de-prueba',
    httpClient: MockClient((_) async => response),
  );
}

/// Respuesta con el cuerpo en UTF-8 y sin charset en el Content-Type, igual
/// que la que manda nuestra API en Go.
http.Response jsonResponse(String body, {int status = 200}) {
  return http.Response.bytes(
    utf8.encode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  group('ProgramSummary.fromJson', () {
    test('lee un programa sin descripción', () {
      final p = ProgramSummary.fromJson({
        'slug': 'ring-master',
        'name': 'Ring Master',
        'description': null,
        'session_count': 40,
      });

      expect(p.slug, 'ring-master');
      expect(p.sessionCount, 40);
      expect(p.description, isNull);
    });

    test('rechaza un JSON con tipos inesperados', () {
      expect(
        () => ProgramSummary.fromJson({
          'slug': 'x',
          'name': 'X',
          'description': null,
          'session_count': '40', // string en vez de int
        }),
        throwsFormatException,
      );
    });
  });

  group('CatalogClient.fetchPrograms', () {
    test('pide GET /programs y devuelve la lista', () async {
      late Uri requested;
      late Map<String, String> headers;
      final client = CatalogClient(
        baseUrl: 'http://backend.test',
        accessToken: () => 'token-de-prueba',
        httpClient: MockClient((request) async {
          requested = request.url;
          headers = request.headers;
          return jsonResponse(
            '[{"slug":"unbreakable","name":"Unbreakable","description":null,"session_count":50}]',
          );
        }),
      );

      final programs = await client.fetchPrograms();

      expect(requested.toString(), 'http://backend.test/programs');
      expect(headers['Authorization'], 'Bearer token-de-prueba');
      expect(programs.single.name, 'Unbreakable');
      expect(programs.single.sessionCount, 50);
    });

    test('decodifica los acentos como UTF-8', () async {
      final client = clientReturning(
        jsonResponse(
          '[{"slug":"elite","name":"Élite","description":"Sesión","session_count":1}]',
        ),
      );

      final program = (await client.fetchPrograms()).single;

      expect(program.name, 'Élite');
      expect(program.description, 'Sesión');
    });

    test('lanza CatalogException si el servidor no responde 200', () async {
      final client = clientReturning(
        jsonResponse('{"error":"interno"}', status: 500),
      );

      await expectLater(
        client.fetchPrograms(),
        throwsA(isA<CatalogException>()),
      );
    });

    test('lanza CatalogException si no hay conexión', () async {
      final client = CatalogClient(
        baseUrl: 'http://backend.test',
        accessToken: () => null,
        httpClient: MockClient((_) => throw const SocketException('sin red')),
      );

      await expectLater(
        client.fetchPrograms(),
        throwsA(isA<CatalogException>()),
      );
    });

    test(
      'sin sesión no manda Authorization; un 401 es CatalogException',
      () async {
        late Map<String, String> headers;
        final client = CatalogClient(
          baseUrl: 'http://backend.test',
          accessToken: () => null,
          httpClient: MockClient((request) async {
            headers = request.headers;
            return jsonResponse('{"error":"falta el token"}', status: 401);
          }),
        );

        await expectLater(
          client.fetchPrograms(),
          throwsA(isA<CatalogException>()),
        );
        expect(headers.containsKey('Authorization'), isFalse);
      },
    );
  });
}
