import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/exercise_screen.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/common/api_client.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/training/execution/execution_screen.dart';
import 'package:naguan_app/training/execution/workout_runner.dart';
import 'package:naguan_app/training/training_models.dart';

import '../catalog/fake_catalog_client.dart';
import '../common/memory_local_store.dart';
import 'workout_runner_test.dart' show FakeClock;

/// Una Fragua mínima: 10 sentadillas y 20 s de descanso.
final session = Session.fromJson({
  'id': 5,
  'kind': 'workout',
  'title': 'Mínima',
  'description': null,
  'blocks': [
    {
      'position': 1,
      'type': 'rounds_with_rest',
      'items': [
        {
          'id': 1,
          'round': 1,
          'position': 1,
          'kind': 'exercise',
          'exercise': {'slug': 'sentadilla', 'name': 'Sentadilla'},
          'reps': 10,
        },
        {'id': 2, 'round': 1, 'position': 2, 'kind': 'rest', 'duration_s': 20},
      ],
    },
  ],
});

/// Una serie de press con carga.
final loadedSession = Session.fromJson({
  'id': 6,
  'kind': 'workout',
  'title': 'Con carga',
  'description': null,
  'blocks': [
    {
      'position': 1,
      'type': 'rounds',
      'items': [
        {
          'id': 1,
          'round': 1,
          'position': 1,
          'kind': 'exercise',
          'exercise': {'slug': 'press', 'name': 'Press', 'loaded': true},
          'reps': 5,
        },
      ],
    },
  ],
});

void main() {
  testWidgets('propone el último peso, se ajusta y se registra', (
    tester,
  ) async {
    final training = FakeTrainingClient()..lastLoads = {'press': 60};
    final store = MemoryLocalStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: ExecutionScreen(
          session: loadedSession,
          catalog: FakeCatalogClient(),
          training: fakeServices(client: training, store: store),
          keepScreenOn: false,
        ),
      ),
    );
    // Los últimos pesos llegan mientras se mira PRIMER GOLPE.
    await tester.pump();
    await tester.tap(find.text('EMPEZAR'));
    await tester.pump();

    expect(find.text('60'), findsOneWidget);
    expect(find.text('KG'), findsOneWidget);
    await tester.tap(find.byTooltip('Más peso'));
    await tester.pump();
    expect(find.text('62,5'), findsOneWidget);

    // Tocando el número se escribe el exacto (con coma). pumpAndSettle deja
    // terminar la animación de cierre del diálogo: ahí es donde rompía
    // liberar el controller antes de tiempo.
    await tester.tap(find.text('62,5'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '63,75');
    await tester.tap(find.text('LISTO').last);
    await tester.pumpAndSettle();
    expect(find.text('63,75'), findsOneWidget);

    await tester.tap(find.text('LISTO'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(training.recorded.single.items.single.loadKg, 63.75);

    training.recordCalls.single.complete(
      const WorkoutResult(id: 1, newRecords: []),
    );
    await tester.pumpAndSettle();
    // Queda guardado en el teléfono para proponerlo la próxima vez.
    expect(await fakeServices(store: store).lastLoads.cached(), {
      'press': 63.75,
    });
  });

  testWidgets('recorre la Fragua, la registra y muestra TEMPLADO', (
    tester,
  ) async {
    final clock = FakeClock();
    final training = FakeTrainingClient();
    final beeper = FakeBeeper();
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: ExecutionScreen(
          session: session,
          catalog: FakeCatalogClient(),
          training: fakeServices(client: training, beeper: beeper),
          clock: clock.now,
          keepScreenOn: false,
        ),
      ),
    );

    // PRIMER GOLPE: qué se viene, con el reloj quieto hasta EMPEZAR.
    expect(find.text('PRIMER GOLPE'), findsOneWidget);
    expect(find.text('×10'), findsOneWidget);
    await tester.tap(find.text('EMPEZAR'));
    await tester.pump();

    // Paso 1: sentadillas por reps. Hizo 12 (dos más de las indicadas).
    expect(find.text('SENTADILLA'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);
    await tester.tap(find.byTooltip('Una más'));
    await tester.tap(find.byTooltip('Una más'));
    await tester.pump();
    expect(find.text('12'), findsOneWidget);
    await tester.tap(find.text('LISTO'));
    await tester.pump();

    // Paso 2: el descanso, con cuenta regresiva.
    expect(find.text('ENFRIÁ'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);

    // Pasan los 20 s: se adelanta el reloj del runner, y tester.pump avanza
    // el tiempo simulado del test para que el Timer periódico dispare. A los
    // 18 s (quedan 2) pita la cuenta; en el 0, el piiii.
    clock.advance(const Duration(seconds: 18));
    await tester.pump(const Duration(milliseconds: 300));
    clock.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(beeper.played, [Cue.count, Cue.go]);

    // Terminó: se registró la Fragua con las 12 reps.
    expect(training.recorded, hasLength(1));
    final sent = training.recorded.single;
    expect(sent.sessionId, 5);
    expect(sent.items.single.reps, 12);

    training.recordCalls.single.complete(
      const WorkoutResult(
        id: 1,
        newRecords: [
          Record(
            exercise: 'Sentadilla',
            metric: RecordMetric.reps,
            value: 12,
            previous: 10,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TEMPLADO.'), findsOneWidget);
    expect(find.text('NUEVO MOJÓN'), findsOneWidget);
  });

  testWidgets('"atrás" a mitad de la Fragua pide confirmación', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: ExecutionScreen(
          session: session,
          catalog: FakeCatalogClient(),
          training: fakeServices(),
          clock: FakeClock().now,
          keepScreenOn: false,
        ),
      ),
    );

    await tester.tap(find.text('EMPEZAR'));
    await tester.pump();

    // Simula el botón/gesto "atrás" del sistema.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();

    expect(find.text('¿DEJAR LA FRAGUA?'), findsOneWidget);
    await tester.tap(find.text('SEGUIR'));
    await tester.pump();
    expect(find.text('SENTADILLA'), findsOneWidget);
  });

  testWidgets('antes de EMPEZAR, "atrás" sale sin preguntar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: const Scaffold(body: Text('SESIÓN')),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ExecutionScreen(
          session: session,
          catalog: FakeCatalogClient(),
          training: fakeServices(),
          clock: FakeClock().now,
          keepScreenOn: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PRIMER GOLPE'), findsOneWidget);

    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('¿DEJAR LA FRAGUA?'), findsNothing);
    expect(find.text('SESIÓN'), findsOneWidget);
  });

  testWidgets('guarda la Fragua en curso y, sin señal, la encola', (
    tester,
  ) async {
    final clock = FakeClock();
    final client = FakeTrainingClient();
    final store = MemoryLocalStore();
    final services = fakeServices(client: client, store: store);
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: ExecutionScreen(
          session: session,
          catalog: FakeCatalogClient(),
          training: services,
          clock: clock.now,
          keepScreenOn: false,
        ),
      ),
    );

    // En PRIMER GOLPE no se guarda nada: todavía no hay qué retomar.
    await tester.pump(const Duration(milliseconds: 300));
    expect(await services.activeWorkout.load(now: clock.now()), isNull);
    await tester.tap(find.text('EMPEZAR'));

    // Mientras se entrena, el snapshot queda en el disco (para retomar).
    await tester.pump(const Duration(milliseconds: 300));
    expect(await services.activeWorkout.load(now: clock.now()), isNotNull);

    await tester.tap(find.text('LISTO'));
    clock.advance(const Duration(seconds: 20));
    await tester.pump(const Duration(milliseconds: 300));

    // El registro falla sin conexión (ApiException sin status).
    client.recordCalls.single.completeError(const ApiException('sin red'));
    await tester.pumpAndSettle();

    expect(find.text('TEMPLADO.'), findsOneWidget);
    expect(find.textContaining('Sin señal'), findsOneWidget);
    final queued = await services.pending.list();
    expect(queued.single.clientId, client.recorded.single.clientId);
    // Ya no hay Fragua en curso: quedó en la cola.
    expect(await services.activeWorkout.load(now: clock.now()), isNull);
  });

  testWidgets('"cómo se hace" pausa la Fragua y abre el ejercicio', (
    tester,
  ) async {
    final catalog = FakeCatalogClient();
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: ExecutionScreen(
          session: session,
          catalog: catalog,
          training: fakeServices(),
          clock: FakeClock().now,
          keepScreenOn: false,
        ),
      ),
    );

    await tester.tap(find.text('EMPEZAR'));
    await tester.pump();
    await tester.tap(find.text('CÓMO SE HACE'));
    await tester.pump();

    expect(catalog.requestedSlugs, ['sentadilla']);
    expect(find.byType(ExerciseScreen, skipOffstage: false), findsOneWidget);

    // Volver: la Fragua sigue pausada (se retoma con ▶).
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(); // el pop
    await tester.pump(const Duration(seconds: 1)); // la transición
    expect(find.text('EN PAUSA'), findsOneWidget);
    expect(find.byTooltip('Seguir'), findsOneWidget);
  });
}
