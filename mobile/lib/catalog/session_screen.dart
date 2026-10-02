import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/format.dart';
import 'package:naguan_app/catalog/item_editor_sheet.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/catalog/session_edits.dart';
import 'package:naguan_app/common/load_view.dart';
import 'package:naguan_app/theme/forja_pill.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/training/execution/execution_screen.dart';
import 'package:naguan_app/training/training_services.dart';
import 'package:naguan_app/theme/forja_headline.dart';
import 'package:naguan_app/common/markdown_text.dart';

/// Lo que hay que hacer al tocar un ejercicio: el bloque donde está, para
/// saber qué ítems ajustar.
typedef OnEditItem = void Function(Block block, Item item);

/// Una Fragua (sesión): su descripción y sus bloques, vuelta por vuelta, y
/// el botón para empezarla.
///
/// Antes de empezar, cada ejercicio se puede ajustar (reps, segundos, o
/// cambiarlo por una progresión). Los ajustes valen solo para esta vez:
/// viven en el State de esta pantalla y se pierden al salir.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.catalog,
    required this.training,
    required this.id,
    required this.label,
  });

  final CatalogClient catalog;
  final TrainingServices training;
  final int id;

  /// Contexto que viene de la pantalla anterior: "UNBREAKABLE · FRAGUA 01".
  final String label;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  /// La Fragua ajustada; null si no difiere de la que vino de la API.
  ///
  /// Invariante: _plan es null o DISTINTO del original. Por eso alcanza con
  /// mirar si es null para mostrar ORIGINAL, y _edit lo mantiene: si un
  /// ajuste deja todo como estaba (se subió una rep y se volvió a bajar),
  /// guarda null y no una copia idéntica.
  Session? _plan;

  /// Se guarda la función de carga (y no se escribe como lambda en build):
  /// LoadView la llama una vez al montarse y en cada reintento.
  Future<Session> _load() => widget.catalog.fetchSession(widget.id);

  Future<void> _edit(
    Session original,
    Session plan,
    Block block,
    Item item,
  ) async {
    final edit = await showItemEditor(
      context,
      catalog: widget.catalog,
      item: item,
    );
    // null: la hoja se cerró sin LISTO. mounted: la pantalla pudo cerrarse
    // mientras la hoja estaba abierta.
    if (edit == null || !mounted) return;
    final next = plan.adjust(
      blockPosition: block.position,
      item: item,
      value: edit.value,
      exercise: edit.exercise,
    );
    setState(() => _plan = next.sameAs(original) ? null : next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (_plan != null)
            TextButton(
              onPressed: () => setState(() => _plan = null),
              child: const Text('ORIGINAL'),
            ),
        ],
      ),
      body: LoadView<Session>(
        load: _load,
        builder: (context, original) {
          final plan = _plan ?? original;
          return Column(
            children: [
              Expanded(
                child: _SessionDetail(
                  label: widget.label,
                  session: plan,
                  original: original,
                  // Las filas no saben editar ni conocen el cliente: reciben
                  // qué hacer al tocarlas, como un @Output de Angular o un
                  // callback de React.
                  onEditItem: (block, item) =>
                      _edit(original, plan, block, item),
                ),
              ),
              // El CTA fijo abajo, fuera del scroll: siempre a mano.
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(ForjaSpace.s4),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      // Se ejecuta el plan (ajustado o no): para el motor
                      // es una sesión como cualquier otra.
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ExecutionScreen(
                            session: plan,
                            catalog: widget.catalog,
                            training: widget.training,
                          ),
                        ),
                      ),
                      child: const Text('A LA FRAGUA'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SessionDetail extends StatelessWidget {
  const _SessionDetail({
    required this.label,
    required this.session,
    required this.original,
    required this.onEditItem,
  });

  final String label;
  final Session session;

  /// La Fragua sin ajustes, para marcar qué filas cambiaron.
  final Session original;
  final OnEditItem onEditItem;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Los ítems originales por id, armado una vez por build: cada fila
    // busca el suyo para saber si cambió (y por cuál ejercicio).
    final originals = {
      for (final b in original.blocks)
        for (final i in b.items) i.id: i,
    };

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
        ForjaHeadline(
          session.title.toUpperCase(),
          style: textTheme.displayMedium,
        ),
        if (session.description case final description?) ...[
          const SizedBox(height: ForjaSpace.s4),
          // Las descripciones traen listas ("- 4 superSets..."): el mismo
          // Markdown mínimo que en la pantalla de un ejercicio.
          MarkdownText(description),
        ],
        const SizedBox(height: ForjaSpace.s4),
        Text(
          'Tocá un ejercicio para ajustar las reps o cambiarlo.',
          style: textTheme.bodyLarge?.copyWith(
            color: context.forja.palette.inkMuted,
          ),
        ),
        // Collection for: un _BlockCard (y su separación) por bloque.
        for (final block in session.blocks) ...[
          const SizedBox(height: ForjaSpace.s6),
          _BlockCard(
            block: block,
            originals: originals,
            onEditItem: onEditItem,
          ),
        ],
      ],
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.block,
    required this.originals,
    required this.onEditItem,
  });

  final Block block;
  final Map<int, Item> originals;
  final OnEditItem onEditItem;

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
            // Wrap y no Row: si el título y la pill no entran en un renglón
            // (VUELTAS CON PAUSA en un teléfono angosto), la pill baja al
            // siguiente en vez de pisar el título. spaceBetween la manda a
            // la derecha cuando sí entran, como hacía el Spacer.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: ForjaSpace.s4,
              runSpacing: ForjaSpace.s2,
              children: [
                Text('BLOQUE ${block.position}', style: textTheme.titleLarge),
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
              for (final item in group.items)
                _ItemRow(
                  item: item,
                  original: originals[item.id],
                  onTap: () => onEditItem(block, item),
                ),
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
  const _ItemRow({
    required this.item,
    required this.original,
    required this.onTap,
  });

  final Item item;

  /// El ítem como vino de la API, para marcar lo ajustado.
  final Item? original;
  final VoidCallback onTap;

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
    // Lo ajustado va en rosa (accentText): "esto no es lo que indica la
    // Senda". Siempre acompañado de texto (EN LUGAR DE...) o del número,
    // nunca solo el color.
    final swappedFrom = original?.exercise?.slug != item.exercise?.slug
        ? original?.exercise
        : null;
    final retargeted =
        original != null &&
        (original!.reps != item.reps || original!.durationS != item.durationS);
    final accentLabel = textTheme.labelSmall?.copyWith(
      color: forja.palette.accentText,
    );

    final Widget name;
    if (item.exercise case final exercise?) {
      name = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(exercise.name, style: forja.bodyStrong),
          if (swappedFrom != null)
            Text(
              'EN LUGAR DE ${swappedFrom.name.toUpperCase()}',
              style: accentLabel,
            ),
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

    final exercise = item.exercise;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: ForjaSpace.s1),
      child: Row(
        children: [
          Expanded(child: name),
          const SizedBox(width: ForjaSpace.s4),
          Text(
            metric,
            style: retargeted
                ? metricStyle.copyWith(color: forja.palette.accentText)
                : metricStyle,
          ),
          // El chevron avisa que la fila se puede tocar. En los descansos
          // va un hueco del mismo ancho, para que las métricas queden
          // alineadas en columna.
          SizedBox(
            width: ForjaSpace.s6,
            child: exercise == null
                ? null
                : Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: forja.palette.inkMuted,
                  ),
          ),
        ],
      ),
    );

    // Los descansos no se ajustan.
    if (exercise == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
