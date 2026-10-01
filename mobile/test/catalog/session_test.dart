import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/catalog/format.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/catalog/session_screen.dart';
import 'package:naguan_app/theme/forja_theme.dart';

import 'fake_catalog_client.dart';

/// Una sesión como la manda la API: los campos opcionales (time_cap_s,
/// exercise, side, duration_s, reps) se omiten cuando no aplican.
const sessionJson = {
  'id': 1,
  'kind': 'workout',
  'title': 'Tábata',
  'description': null,
  'blocks': [
    {
      'position': 1,
      'type': 'rounds_with_rest',
      'items': [
        {
          'round': 1,
          'position': 1,
          'kind': 'exercise',
          'exercise': {'slug': 'plancha-lateral', 'name': 'Plancha lateral'},
          'side': 'right',
          'duration_s': 60,
        },
        {'round': 1, 'position': 2, 'kind': 'rest', 'duration_s': 40},
        {
          'round': 2,
          'position': 1,
          'kind': 'exercise',
          'exercise': {'slug': 'plancha-lateral', 'name': 'Plancha lateral'},
          'side': 'left',
          'duration_s': 60,
        },
      ],
    },
    {
      'position': 2,
      'type': 'amrap',
      'time_cap_s': 900,
      'items': [
        {
          'round': 1,
          'position': 1,
          'kind': 'exercise',
          'exercise': {'slug': 'flexion', 'name': 'Flexión'},
          'reps': 10,
        },
      ],
    },
  ],
};

void main() {
  group('Session.fromJson', () {
    test('lee bloques, vueltas, lados y descansos', () {
      final session = Session.fromJson(sessionJson);

      expect(session.title, 'Tábata');
      expect(session.blocks, hasLength(2));

      final first = session.blocks.first;
      expect(first.type, BlockType.roundsWithRest);
      expect(first.timeCapS, isNull);
      expect(first.rounds, hasLength(2));
      expect(first.rounds[0], hasLength(2));
      expect(first.items[0].side, Side.right);
      expect(first.items[1].isRest, isTrue);

      final amrap = session.blocks.last;
      expect(amrap.type, BlockType.amrap);
      expect(amrap.timeCapS, 900);
      expect(amrap.items.single.reps, 10);
    });

    test('rechaza un tipo de bloque desconocido', () {
      expect(
        () => Session.fromJson({
          ...sessionJson,
          'blocks': [
            {'position': 1, 'type': 'zumba', 'items': []},
          ],
        }),
        throwsFormatException,
      );
    });
  });

  group('Block.roundGroups', () {
    Map<String, dynamic> exercise(int round, {int? reps, int? seconds}) => {
      'round': round,
      'position': 1,
      'kind': 'exercise',
      'exercise': {'slug': 'flexion', 'name': 'Flexión'},
      'reps': ?reps,
      'duration_s': ?seconds,
    };
    Map<String, dynamic> rest(int round, int seconds) => {
      'round': round,
      'position': 2,
      'kind': 'rest',
      'duration_s': seconds,
    };
    Block block(String type, List<Map<String, dynamic>> items) =>
        Block.fromJson({'position': 1, 'type': type, 'items': items});

    test('agrupa vueltas iguales y corta en la que cambia', () {
      // 3 vueltas de 10 flexiones + 20 s; la 4ta descansa 60 s.
      final b = block('rounds_with_rest', [
        for (var r = 1; r <= 3; r++) ...[exercise(r, reps: 10), rest(r, 20)],
        exercise(4, reps: 10),
        rest(4, 60),
      ]);

      final groups = b.roundGroups;

      expect(groups, hasLength(2));
      expect((groups[0].firstRound, groups[0].count), (1, 3));
      expect((groups[1].firstRound, groups[1].count), (4, 1));
      expect(groups[1].items.last.durationS, 60);
    });

    test('no agrupa una escalera (las reps cambian en cada vuelta)', () {
      final b = block('ladder', [
        for (var r = 1; r <= 5; r++) exercise(r, reps: 6 - r),
      ]);

      expect(b.roundGroups.map((g) => g.count), everyElement(1));
    });
  });

  group('formatDuration', () {
    const cases = {
      10: '10 s',
      90: '90 s',
      120: '2 min',
      150: '2:30',
      900: '15 min',
    };
    for (final MapEntry(key: seconds, value: want) in cases.entries) {
      test('$seconds → $want', () => expect(formatDuration(seconds), want));
    }
  });

  testWidgets('SessionScreen muestra bloques, vueltas y métricas', (
    tester,
  ) async {
    final client = FakeCatalogClient();
    await tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        home: SessionScreen(client: client, id: 1, label: 'X · FRAGUA 01'),
      ),
    );

    client.sessionCalls.single.complete(Session.fromJson(sessionJson));
    await tester.pump();

    expect(client.requestedSessionIds, [1]);
    expect(find.text('TÁBATA'), findsOneWidget);
    expect(find.text('VUELTAS CON PAUSA'), findsOneWidget);
    // Las vueltas 1 y 2 difieren en el lado: no se agrupan.
    expect(find.text('VUELTA 2'), findsOneWidget);
    expect(find.text('DERECHA'), findsOneWidget);
    expect(find.text('ENFRIÁ'), findsOneWidget);
    expect(find.text('40 s'), findsOneWidget);

    // El amrap: tope en la pill, sin numerar vueltas.
    expect(find.text('AMRAP · 15 MIN'), findsOneWidget);
    expect(find.text('×10'), findsOneWidget);
  });
}
