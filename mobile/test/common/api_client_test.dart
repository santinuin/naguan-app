import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:naguan_app/common/api_client.dart';
import 'package:naguan_app/training/training_client.dart';
import 'package:naguan_app/training/training_models.dart';

/// Respuesta con el cuerpo en UTF-8 y sin charset en el Content-Type, igual
/// que la que manda nuestra API en Go.
http.Response jsonResponse(String body, {int status = 200}) {
  return http.Response.bytes(
    utf8.encode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

/// Un ApiClient contra un MockClient que guarda el último request.
(ApiClient, List<http.Request>) apiReturning(
  http.Response response, {
  String? token = 'token-de-prueba',
}) {
  final requests = <http.Request>[];
  final api = ApiClient(
    baseUrl: 'http://backend.test/v1',
    accessToken: () => token,
    httpClient: MockClient((request) async {
      requests.add(request);
      return response;
    }),
  );
  return (api, requests);
}

void main() {
  group('ApiClient', () {
    test('manda el token y decodifica los acentos como UTF-8', () async {
      final (api, requests) = apiReturning(jsonResponse('{"title":"Sesión"}'));

      final json = await api.getJson('/sessions/1');

      expect(json, {'title': 'Sesión'});
      expect(
        requests.single.url.toString(),
        'http://backend.test/v1/sessions/1',
      );
      expect(
        requests.single.headers['Authorization'],
        'Bearer token-de-prueba',
      );
    });

    test('sin sesión no manda Authorization', () async {
      final (api, requests) = apiReturning(jsonResponse('{}'), token: null);

      await api.getJson('/x');

      expect(requests.single.headers.containsKey('Authorization'), isFalse);
    });

    test('POST manda el cuerpo como JSON', () async {
      final (api, requests) = apiReturning(
        jsonResponse('{"id":1}', status: 201),
      );

      await api.postJson('/me/workouts', {'session_id': 3});

      expect(requests.single.method, 'POST');
      expect(jsonDecode(requests.single.body), {'session_id': 3});
      expect(
        requests.single.headers['Content-Type'],
        startsWith('application/json'),
      );
    });

    test('un 204 sin cuerpo devuelve null', () async {
      final (api, _) = apiReturning(http.Response('', 204));

      await api.delete('/me/programs/aurum/progress');
    });

    test('un error usa el mensaje de la API y guarda el status', () async {
      final (api, _) = apiReturning(
        jsonResponse('{"error":"el ítem 5 es un descanso"}', status: 400),
      );

      await expectLater(
        api.getJson('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'el ítem 5 es un descanso')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('sin conexión es ApiException sin status', () async {
      final api = ApiClient(
        baseUrl: 'http://backend.test',
        accessToken: () => null,
        httpClient: MockClient((_) => throw const SocketException('sin red')),
      );

      await expectLater(
        api.getJson('/x'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', isNull),
        ),
      );
    });
  });

  group('TrainingClient', () {
    test('las stats mandan el día local del teléfono', () async {
      final (api, requests) = apiReturning(
        jsonResponse('{"brasa":{"days":3,"at_risk":true},"total_workouts":9}'),
      );

      final stats = await TrainingClient(api).fetchStats(
        now: DateTime(2026, 10, 1, 23, 30), // hora local
      );

      expect(requests.single.url.queryParameters['today'], '2026-10-01');
      expect(stats.brasa.days, 3);
      expect(stats.brasa.atRisk, isTrue);
    });

    test('el detalle del progreso trae los checks como Set', () async {
      final (api, _) = apiReturning(
        jsonResponse(
          '{"program":{"slug":"aurum","name":"Aurum"},"completed_sessions":2,'
          '"total_sessions":12,"next_session":{"position":1,"id":180,"title":"S1"},'
          '"reset_at":null,"completed_session_ids":[182,185]}',
        ),
      );

      final p = await TrainingClient(api).fetchProgramProgress('aurum');

      expect(p.completedSessionIds, {182, 185});
      expect(p.next?.position, 1);
    });

    test(
      'registrar una Fragua manda local_date y devuelve los mojones',
      () async {
        final (api, requests) = apiReturning(
          jsonResponse(
            '{"id":7,"new_records":[{"exercise":"Sentadilla","metric":"reps",'
            '"value":14,"previous":10}]}',
            status: 201,
          ),
        );
        final workout = NewWorkout(
          clientId: '0f8fad5b-d9cb-469f-a165-70867728950e',
          sessionId: 3,
          startedAt: DateTime.utc(2026, 10, 1, 20),
          finishedAt: DateTime.utc(2026, 10, 1, 20, 40),
          items: const [ItemResult.reps(10, 14)],
        );

        final result = await TrainingClient(api).recordWorkout(workout);

        final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
        expect(body['finished_at'], '2026-10-01T20:40:00.000Z');
        expect(body['client_id'], '0f8fad5b-d9cb-469f-a165-70867728950e');
        expect(body['local_date'], isA<String>());
        expect(body['items'], [
          {'block_item_id': 10, 'reps': 14},
        ]);
        expect(result.newRecords.single.previous, 10);
      },
    );
  });

  test('un 401 avisa con onUnauthorized (para cerrar la sesión)', () async {
    var called = 0;
    final api = ApiClient(
      baseUrl: 'http://backend.test',
      accessToken: () => 'vencido',
      onUnauthorized: () => called++,
      httpClient: MockClient((_) async => jsonResponse('{}', status: 401)),
    );

    await expectLater(api.getJson('/x'), throwsA(isA<ApiException>()));
    expect(called, 1);
  });
}
