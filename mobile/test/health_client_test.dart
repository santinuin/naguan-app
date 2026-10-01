import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:naguan_app/health_client.dart';

void main() {
  group('HealthClient.fetchStatus', () {
    test('devuelve el status cuando el backend responde 200', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.toString(), 'http://backend.test/health');
        return http.Response('{"status":"ok"}', 200);
      });
      final client = HealthClient(
        baseUrl: 'http://backend.test',
        httpClient: mock,
      );

      expect(await client.fetchStatus(), 'ok');
    });

    test('lanza una excepción si el backend no responde 200', () async {
      final mock = MockClient((_) async => http.Response('caído', 503));
      final client = HealthClient(
        baseUrl: 'http://backend.test',
        httpClient: mock,
      );

      await expectLater(client.fetchStatus(), throwsA(isA<Exception>()));
    });
  });
}
