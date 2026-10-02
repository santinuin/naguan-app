import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/common/api_client.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/training/history/dates.dart';
import 'package:naguan_app/training/history/history_screen.dart';
import 'package:naguan_app/training/history/records_screen.dart';
import 'package:naguan_app/training/history/workout_history.dart';
import 'package:naguan_app/training/training_client.dart';
import 'package:naguan_app/training/training_models.dart';

import '../catalog/fake_catalog_client.dart';
import '../common/api_client_test.dart' show apiReturning, jsonResponse;

/// Una Fragua templada de prueba: id y día (local) alcanzan para casi todo.
Workout templada(int id, DateTime day, {String? program = 'Aurum'}) => Workout(
  id: id,
  sessionId: 100 + id,
  sessionTitle: 'Sesión $id',
  programName: program,
  finishedAt: day.add(const Duration(hours: 20)),
  localDate: day,
  durationS: 1920,
);

/// [count] Fraguas con ids descendentes desde [from], todas del mismo día.
List<Workout> page(int from, int count) => [
  for (var i = 0; i < count; i++) templada(from - i, DateTime(2026, 10, 1)),
];

void main() {
  group('modelos y cliente', () {
    test('pide el historial con el cursor y lo parsea', () async {
      final (api, requests) = apiReturning(
        jsonResponse('''[{
          "id": 7,
          "session": {"id": 3, "title": "Sesión 3"},
          "program": {"slug": "aurum", "name": "Aurum"},
          "started_at": "2026-10-01T23:00:00Z",
          "finished_at": "2026-10-01T23:32:00Z",
          "local_date": "2026-10-01",
          "duration_s": 1920
        }, {
          "id": 6,
          "session": {"id": 9, "title": "Movilidad"},
          "program": null,
          "started_at": "2026-09-30T10:00:00Z",
          "finished_at": "2026-09-30T10:10:00Z",
          "local_date": "2026-09-30",
          "duration_s": 600
        }]'''),
      );

      final got = await TrainingClient(api).fetchWorkouts(before: 9, limit: 2);

      expect(requests.single.url.query, 'limit=2&before=9');
      expect(got.map((w) => w.id), [7, 6]);
      expect(got.first.programName, 'Aurum');
      expect(got.first.sessionTitle, 'Sesión 3');
      expect(got.first.localDate, DateTime(2026, 10, 1));
      expect(got.last.programName, isNull); // sesión suelta
    });

    test('un Mojón trae el slug y el día, si la API los manda', () {
      final record = Record.fromJson({
        'exercise': 'Dominada',
        'exercise_slug': 'dominada',
        'metric': 'reps',
        'value': 15,
        'achieved_on': '2026-09-15',
      });
      expect(record.exerciseSlug, 'dominada');
      expect(record.achievedOn, DateTime(2026, 9, 15));

      // Una API anterior: sin slug ni día, el Mojón se lee igual.
      final old = Record.fromJson({
        'exercise': 'Plancha',
        'metric': 'duration_s',
        'value': 60,
      });
      expect(old.isReps, isFalse);
      expect(old.exerciseSlug, isNull);
      expect(old.achievedOn, isNull);
    });

    test('fechas en castellano', () {
      final d = DateTime(2026, 10, 1); // un jueves
      expect(weekdayShort(d), 'JUE');
      expect(formatDate(d), '1 OCT 2026');
      expect(formatMonth(d), 'OCTUBRE 2026');
      expect(sameMonth(d, DateTime(2026, 10, 31)), isTrue);
      expect(sameMonth(d, DateTime(2025, 10, 1)), isFalse);
    });
  });

  group('WorkoutHistory', () {
    test('pagina con el id de la última Fragua como cursor', () async {
      final client = FakeTrainingClient();
      final history = WorkoutHistory(client, pageSize: 2);

      final first = history.loadMore();
      expect(history.loading, isTrue);
      // Llamarla de nuevo con una página en camino no pide otra.
      history.loadMore();
      expect(client.workoutsCalls, hasLength(1));

      client.workoutsCalls.last.complete(page(10, 2));
      await first;
      expect(history.workouts.map((w) => w.id), [10, 9]);
      expect(history.hasMore, isTrue);

      final second = history.loadMore();
      client.workoutsCalls.last.complete(page(8, 1)); // incompleta: la última
      await second;

      expect(client.workoutsBefore, [null, 9]);
      expect(history.workouts.map((w) => w.id), [10, 9, 8]);
      expect(history.hasMore, isFalse);

      // Sin más páginas, no se piden más.
      await history.loadMore();
      expect(client.workoutsCalls, hasLength(2));
    });

    test('un error conserva lo cargado y se puede reintentar', () async {
      final client = FakeTrainingClient();
      final history = WorkoutHistory(client, pageSize: 2);

      final first = history.loadMore();
      client.workoutsCalls.last.complete(page(10, 2));
      await first;

      final failing = history.loadMore();
      client.workoutsCalls.last.completeError(const ApiException('sin red'));
      await failing;
      expect(history.failed, isTrue);
      expect(history.workouts, hasLength(2));

      final retry = history.loadMore();
      expect(history.failed, isFalse);
      client.workoutsCalls.last.complete(const []);
      await retry;
      expect(client.workoutsBefore, [null, 9, 9]); // el mismo cursor
      expect(history.hasMore, isFalse);
    });

    test('descartado con una página en camino, ignora la respuesta', () async {
      final client = FakeTrainingClient();
      final history = WorkoutHistory(client);

      final loading = history.loadMore();
      history.dispose();
      client.workoutsCalls.last.complete(page(10, 1));

      // Sin la guarda de _disposed, esto fallaría: notifyListeners sobre
      // un ChangeNotifier descartado.
      await loading;
    });
  });

  group('HistoryScreen', () {
    Future<FakeTrainingClient> pumpHistory(WidgetTester tester) async {
      final client = FakeTrainingClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: forjaHierro,
          home: HistoryScreen(
            catalog: FakeCatalogClient(),
            training: fakeServices(client: client),
          ),
        ),
      );
      return client;
    }

    testWidgets('muestra las Fraguas agrupadas por mes', (tester) async {
      final client = await pumpHistory(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      client.workoutsCalls.single.complete([
        templada(3, DateTime(2026, 10, 1)),
        templada(2, DateTime(2026, 9, 29), program: null),
        templada(1, DateTime(2026, 9, 2)),
      ]);
      await tester.pump();

      expect(find.text('HISTORIAL'), findsOneWidget);
      expect(find.text('OCTUBRE 2026'), findsOneWidget);
      // Un solo encabezado para las dos de septiembre.
      expect(find.text('SEPTIEMBRE 2026'), findsOneWidget);
      expect(find.text('Sesión 3'), findsOneWidget);
      expect(find.text('AURUM'), findsNWidgets(2)); // la 2 es suelta
      expect(find.text('JUE'), findsOneWidget);
      expect(find.text('32′'), findsNWidgets(3));
    });

    testWidgets('pide la página siguiente al acercarse al final', (
      tester,
    ) async {
      final client = await pumpHistory(tester);
      client.workoutsCalls.single.complete(page(40, 20)); // página llena
      await tester.pump();
      expect(client.workoutsCalls, hasLength(1));

      // Arrastrar hacia arriba = bajar en la lista.
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pump();

      expect(client.workoutsBefore, [null, 21]);
    });

    testWidgets('sin Fraguas, invita a templar una', (tester) async {
      final client = await pumpHistory(tester);
      client.workoutsCalls.single.complete(const []);
      await tester.pump();

      expect(find.textContaining('Todavía no templaste'), findsOneWidget);
    });
  });

  testWidgets('RecordsScreen muestra cada marca con su día', (tester) async {
    final client = FakeTrainingClient();
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: RecordsScreen(catalog: FakeCatalogClient(), client: client),
      ),
    );

    client.recordsCalls.single.complete([
      Record(
        exercise: 'Dominada',
        exerciseSlug: 'dominada',
        isReps: true,
        value: 15,
        achievedOn: DateTime(2026, 9, 15),
      ),
      const Record(exercise: 'Plancha', isReps: false, value: 60),
    ]);
    await tester.pump();

    expect(find.text('MOJONES'), findsOneWidget);
    expect(find.text('Dominada'), findsOneWidget);
    expect(find.text('×15'), findsOneWidget);
    expect(find.text('15 SEP 2026'), findsOneWidget);
    expect(find.text('60″'), findsOneWidget);
  });
}
