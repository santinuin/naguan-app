import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/common/api_client.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/training/execution/execution_screen.dart';
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

void main() {
  testWidgets('recorre la Fragua, la registra y muestra TEMPLADO', (
    tester,
  ) async {
    final clock = FakeClock();
    final training = FakeTrainingClient();
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: ExecutionScreen(
          session: session,
          training: fakeServices(client: training),
          clock: clock.now,
          keepScreenOn: false,
        ),
      ),
    );

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
    // el tiempo simulado del test para que el Timer periódico dispare.
    clock.advance(const Duration(seconds: 20));
    await tester.pump(const Duration(milliseconds: 300));

    // Terminó: se registró la Fragua con las 12 reps.
    expect(training.recorded, hasLength(1));
    final sent = training.recorded.single;
    expect(sent.sessionId, 5);
    expect(sent.items.single.reps, 12);

    training.recordCalls.single.complete(
      const WorkoutResult(
        id: 1,
        newRecords: [
          Record(exercise: 'Sentadilla', isReps: true, value: 12, previous: 10),
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
          training: fakeServices(),
          clock: FakeClock().now,
          keepScreenOn: false,
        ),
      ),
    );

    // Simula el botón/gesto "atrás" del sistema.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pump();

    expect(find.text('¿DEJAR LA FRAGUA?'), findsOneWidget);
    await tester.tap(find.text('SEGUIR'));
    await tester.pump();
    expect(find.text('SENTADILLA'), findsOneWidget);
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
          training: services,
          clock: clock.now,
          keepScreenOn: false,
        ),
      ),
    );

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
}
