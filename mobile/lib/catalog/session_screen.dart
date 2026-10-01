import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/format.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/common/load_view.dart';
import 'package:naguan_app/theme/forja_pill.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

/// Una Fragua (sesión): su descripción y sus bloques, vuelta por vuelta.
class SessionScreen extends StatelessWidget {
  const SessionScreen({
    super.key,
    required this.client,
    required this.id,
    required this.label,
  });

  final CatalogClient client;
  final int id;

  /// Contexto que viene de la pantalla anterior: "UNBREAKABLE · FRAGUA 01".
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: LoadView<Session>(
        load: () => client.fetchSession(id),
        builder: (context, session) =>
            _SessionDetail(label: label, session: session),
      ),
    );
  }
}

class _SessionDetail extends StatelessWidget {
  const _SessionDetail({required this.label, required this.session});

  final String label;
  final Session session;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // Un ListView con children fijos (no .builder): la sesión tiene pocos
    // bloques, y así el contenido se arma como una columna que scrollea.
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ForjaSpace.s4,
        0,
        ForjaSpace.s4,
        ForjaSpace.s8,
      ),
      children: [
        Text(label, style: textTheme.labelSmall),
        const SizedBox(height: ForjaSpace.s2),
        Text(session.title.toUpperCase(), style: textTheme.displayMedium),
        if (session.description case final description?) ...[
          const SizedBox(height: ForjaSpace.s4),
          Text(description),
        ],
        // Collection for: un _BlockCard (y su separación) por bloque.
        for (final block in session.blocks) ...[
          const SizedBox(height: ForjaSpace.s6),
          _BlockCard(block: block),
        ],
      ],
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block});

  final Block block;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final groups = block.roundGroups;
    final isAmrap = block.type == BlockType.amrap;

    var typeLabel = block.type.label;
    if (block.timeCapS case final cap?) {
      typeLabel += ' · ${formatDuration(cap)}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ForjaSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('BLOQUE ${block.position}', style: textTheme.titleLarge),
                const Spacer(),
                ForjaPill(typeLabel),
              ],
            ),
            if (isAmrap) ...[
              const SizedBox(height: ForjaSpace.s2),
              const Text('Repetí la vuelta hasta que se acabe el tiempo.'),
            ],
            for (final group in groups) ...[
              const SizedBox(height: ForjaSpace.s4),
              // En un amrap hay una sola vuelta escrita que se repite: no
              // tiene sentido numerarla.
              if (!isAmrap)
                Text(_roundsLabel(group), style: textTheme.labelSmall),
              for (final item in group.items) _ItemRow(item: item),
            ],
          ],
        ),
      ),
    );
  }
}

/// "VUELTA 4" para una sola vuelta; "VUELTAS 1–3 · ×3" para un grupo.
String _roundsLabel(RoundGroup group) {
  if (group.count == 1) return 'VUELTA ${group.firstRound}';
  return 'VUELTAS ${group.firstRound}–${group.lastRound} · ×${group.count}';
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final forja = context.forja;
    // Los números en mono tabular (el estilo `stat`), a un tamaño de fila.
    final metricStyle = forja.stat.copyWith(fontSize: 18, height: 1.3);

    final metric = switch (item) {
      Item(:final reps?) => formatReps(reps),
      Item(:final durationS?) => formatDuration(durationS),
      _ => '',
    };

    final Widget name;
    if (item.exercise case final exercise?) {
      name = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(exercise.name, style: forja.bodyStrong),
          if (item.side case final side?)
            Text(side.label, style: textTheme.labelSmall),
        ],
      );
    } else {
      name = Text(
        'ENFRIÁ',
        style: textTheme.labelSmall?.copyWith(fontSize: 14),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ForjaSpace.s1),
      child: Row(
        children: [
          Expanded(child: name),
          const SizedBox(width: ForjaSpace.s4),
          Text(metric, style: metricStyle),
        ],
      ),
    );
  }
}
