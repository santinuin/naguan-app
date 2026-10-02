import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/exercise.dart';
import 'package:naguan_app/catalog/exercise_screen.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/catalog/session_edits.dart';
import 'package:naguan_app/catalog/session_screen.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/training/execution/execution_screen.dart';

import 'exercise_test.dart' show exerciseJson;
import 'fake_catalog_client.dart';
import 'session_test.dart' show sessionJson;

const dominada = ExerciseRef(slug: 'dominada', name: 'Dominada');
const asistida = ExerciseRef(
  slug: 'dominada-asistida',
  name: 'Dominada asistida',
);
const plancha = ExerciseRef(slug: 'plancha-lateral', name: 'Plancha lateral');

/// Un bloque de tres vueltas: dominadas (8, 8 y 5: las dos primeras forman
/// un grupo) y plancha lateral de cada lado (30 s).
Session ladder() {
  var id = 0;
  List<Item> round(int r, int reps) => [
    Item(id: ++id, round: r, position: 1, exercise: dominada, reps: reps),
    Item(
      id: ++id,
      round: r,
      position: 2,
      exercise: plancha,
      side: Side.left,
      durationS: 30,
    ),
    Item(
      id: ++id,
      round: r,
      position: 3,
      exercise: plancha,
      side: Side.right,
      durationS: 30,
    ),
  ];
  return Session(
    id: 1,
    title: 'Escalera',
    blocks: [
      Block(
        position: 1,
        type: BlockType.ladder,
        items: [...round(1, 8), ...round(2, 8), ...round(3, 5)],
      ),
    ],
  );
}

/// Los ítems de la sesión, en orden, como "slug reps/segundos".
List<String> describe(Session s) => [
  for (final i in s.blocks.single.items)
    '${i.exercise!.slug} ${i.reps ?? '${i.durationS}s'}',
];

void main() {
  group('SessionEdits', () {
    test('retarget cambia ese objetivo en todo el bloque, nada más', () {
      final session = ladder();
      final first = session.blocks.single.items.first; // dominada × 8

      final edited = session.retarget(blockPosition: 1, item: first, value: 10);

      expect(describe(edited), [
        'dominada 10', 'plancha-lateral 30s', 'plancha-lateral 30s',
        'dominada 10', 'plancha-lateral 30s', 'plancha-lateral 30s',
        'dominada 5', 'plancha-lateral 30s', 'plancha-lateral 30s', //
      ]);
      // La original no se tocó: los modelos son inmutables.
      expect(describe(session).first, 'dominada 8');
    });

    test('retarget de un lado cambia los dos', () {
      final session = ladder();
      final left = session.blocks.single.items[1]; // plancha izquierda

      final edited = session.retarget(blockPosition: 1, item: left, value: 45);

      expect(
        describe(edited).where((d) => d.startsWith('plancha')),
        everyElement('plancha-lateral 45s'),
      );
    });

    test('swapExercise cambia el ejercicio en todo el bloque', () {
      final edited = ladder().swapExercise(
        blockPosition: 1,
        from: 'dominada',
        to: asistida,
      );

      final slugs = [
        for (final i in edited.blocks.single.items) i.exercise!.slug,
      ];
      expect(slugs.where((s) => s == 'dominada-asistida'), hasLength(3));
      expect(slugs, isNot(contains('dominada')));
      // Mismos ids: el motor y la API reconocen los ítems.
      expect(
        [for (final i in edited.blocks.single.items) i.id],
        [for (final i in ladder().blocks.single.items) i.id],
      );
    });

    test('adjust aplica objetivo y ejercicio juntos', () {
      final session = ladder();

      // Si el cambio de ejercicio fuera primero, retarget ya no
      // encontraría las "dominada" y las reps quedarían en 8.
      final edited = session.adjust(
        blockPosition: 1,
        item: session.blocks.single.items.first,
        value: 12,
        exercise: asistida,
      );

      expect(describe(edited).first, 'dominada-asistida 12');
      expect(describe(edited)[6], 'dominada-asistida 5'); // otra fila
    });

    test('sameAs compara lo que se pide, no la identidad', () {
      final session = ladder();
      final first = session.blocks.single.items.first;
      final there = session.retarget(blockPosition: 1, item: first, value: 9);
      final back = there.retarget(
        blockPosition: 1,
        item: there.blocks.single.items.first,
        value: 8,
      );

      expect(there.sameAs(session), isFalse);
      // Otra instancia, mismos valores: igual.
      expect(back.sameAs(session), isTrue);
    });
  });

  group('SessionScreen', () {
    Future<FakeCatalogClient> pumpSession(WidgetTester tester) async {
      final client = FakeCatalogClient();
      await tester.pumpWidget(
        MaterialApp(
          theme: forjaHierro,
          home: SessionScreen(
            catalog: client,
            training: fakeServices(),
            id: 1,
            label: 'X · FRAGUA 01',
          ),
        ),
      );
      client.sessionCalls.single.complete(Session.fromJson(sessionJson));
      await tester.pump();
      return client;
    }

    /// Toca el ejercicio y responde el pedido de sus progresiones.
    Future<void> openEditor(
      WidgetTester tester,
      FakeCatalogClient client,
      String name,
      Map<String, dynamic> exercise,
    ) async {
      // La fila puede estar fuera de la pantalla del test (800×600):
      // ensureVisible mueve el scroll hasta ella, y el pump dibuja el frame
      // con la posición nueva (sin él, el toque iría a la posición vieja).
      await tester.ensureVisible(find.text(name).first);
      await tester.pump();
      await tester.tap(find.text(name).first);
      await tester.pump();
      client.exerciseCalls.last.complete(Exercise.fromJson(exercise));
      await tester.pumpAndSettle(); // la animación de la hoja termina
    }

    testWidgets('ajusta los segundos, marca la fila y vuelve al original', (
      tester,
    ) async {
      final client = await pumpSession(tester);
      expect(find.text('ORIGINAL'), findsNothing);

      await openEditor(tester, client, 'Plancha lateral', exerciseJson());
      expect(find.text('SEGUNDOS'), findsOneWidget);
      await tester.tap(find.byTooltip('5 segundos más'));
      await tester.tap(find.byTooltip('5 segundos más'));
      await tester.pump();
      expect(find.text('70'), findsOneWidget);
      await tester.tap(find.text('LISTO'));
      await tester.pumpAndSettle();

      // Las dos vueltas (un lado cada una) pasaron a 70 s.
      expect(find.text('60″'), findsNothing);
      expect(find.text('70″'), findsNWidgets(2));
      expect(find.text('ORIGINAL'), findsOneWidget);

      await tester.tap(find.text('ORIGINAL'));
      await tester.pump();
      expect(find.text('60″'), findsNWidgets(2));
    });

    testWidgets('cambia por una progresión y la Fragua usa la ajustada', (
      tester,
    ) async {
      final client = await pumpSession(tester);

      await openEditor(tester, client, 'Plancha lateral', exerciseJson());
      await tester.tap(find.text('Plancha lateral rodillas'));
      await tester.pump();
      // Al elegirla, se piden las progresiones de la nueva.
      expect(client.requestedSlugs.last, 'plancha-lateral-rodillas');
      client.exerciseCalls.last.complete(
        Exercise.fromJson(
          exerciseJson(
            slug: 'plancha-lateral-rodillas',
            name: 'Plancha lateral rodillas',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('VOLVER A PLANCHA LATERAL'), findsOneWidget);
      await tester.tap(find.text('LISTO'));
      await tester.pumpAndSettle();

      expect(find.text('Plancha lateral rodillas'), findsNWidgets(2));
      expect(find.text('EN LUGAR DE PLANCHA LATERAL'), findsNWidgets(2));

      await tester.tap(find.text('A LA FRAGUA'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final execution = tester.widget<ExecutionScreen>(
        find.byType(ExecutionScreen),
      );
      expect(
        execution.session.blocks.first.items.first.exercise!.slug,
        'plancha-lateral-rodillas',
      );
    });

    testWidgets('si los ajustes vuelven al original, ORIGINAL desaparece', (
      tester,
    ) async {
      final client = await pumpSession(tester);

      // Primero se sube a 11 reps...
      await openEditor(tester, client, 'Flexión', exerciseJson());
      await tester.tap(find.byTooltip('Una más'));
      await tester.tap(find.text('LISTO'));
      await tester.pumpAndSettle();
      expect(find.text('×11'), findsOneWidget);
      expect(find.text('ORIGINAL'), findsOneWidget);

      // ...y después se vuelve a 10 a mano: queda igual a la original.
      await openEditor(tester, client, 'Flexión', exerciseJson());
      await tester.tap(find.byTooltip('Una menos'));
      await tester.tap(find.text('LISTO'));
      await tester.pumpAndSettle();
      expect(find.text('×10'), findsOneWidget);
      expect(find.text('ORIGINAL'), findsNothing);
    });

    testWidgets('cerrar la hoja sin LISTO no cambia nada', (tester) async {
      final client = await pumpSession(tester);

      await openEditor(tester, client, 'Flexión', exerciseJson());
      await tester.tap(find.byTooltip('Una más'));
      // Tocar fuera de la hoja la cierra sin valor (pop con null).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('×10'), findsOneWidget);
      expect(find.text('ORIGINAL'), findsNothing);
    });

    testWidgets('desde el editor se abre la pantalla del ejercicio', (
      tester,
    ) async {
      final client = await pumpSession(tester);

      await openEditor(tester, client, 'Plancha lateral', exerciseJson());
      await tester.tap(find.text('CÓMO SE HACE'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ExerciseScreen), findsOneWidget);
    });
  });
}
