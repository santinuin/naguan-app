import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/program.dart';
import 'package:naguan_app/catalog/session_screen.dart';
import 'package:naguan_app/common/load_view.dart';
import 'package:naguan_app/theme/forja_pill.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/training/training_services.dart';
import 'package:naguan_app/training/training_models.dart';

/// Una Senda (programa): sus Fraguas con el check de las templadas, la
/// sugerida para hoy y la opción de resetearla.
///
/// Recibe [name] además de [slug]: la pantalla anterior ya lo conoce, así
/// que el título se muestra al instante mientras se carga el resto.
class ProgramScreen extends StatefulWidget {
  const ProgramScreen({
    super.key,
    required this.catalog,
    required this.training,
    required this.slug,
    required this.name,
  });

  final CatalogClient catalog;
  final TrainingServices training;
  final String slug;
  final String name;

  @override
  State<ProgramScreen> createState() => _ProgramScreenState();
}

class _ProgramScreenState extends State<ProgramScreen> {
  /// Sube para recargar: al volver de una Fragua o después de resetear.
  int _version = 0;

  /// El programa (catálogo) y el progreso del usuario, en paralelo.
  Future<(Program, ProgramProgress)> _load() => (
    widget.catalog.fetchProgram(widget.slug),
    widget.training.client.fetchProgramProgress(widget.slug),
  ).wait;

  void _reload() => setState(() => _version++);

  Future<void> _openSession(SessionSummary session) async {
    final label = 'FRAGUA ${session.position.toString().padLeft(2, '0')}';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionScreen(
          catalog: widget.catalog,
          training: widget.training,
          id: session.id,
          label: '${widget.name.toUpperCase()} · $label',
        ),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿EMPEZAR DE CERO?'),
        content: const Text(
          'Se borran los checks de esta senda. Tu historial, tu brasa y tus '
          'mojones no se tocan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('RESETEAR'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await widget.training.client.resetProgram(widget.slug);
      if (mounted) _reload();
    } on Exception {
      if (!mounted) return;
      // Un SnackBar: el aviso breve que aparece abajo y se va solo. Lo
      // muestra el ScaffoldMessenger, que crea MaterialApp.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo resetear. Probá de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // El AppBar suma solo el botón "atrás" (hay una ruta debajo en la
      // pila) y, a la derecha, la acción de resetear.
      appBar: AppBar(
        actions: [
          TextButton(onPressed: _confirmReset, child: const Text('RESETEAR')),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ForjaSpace.s4,
              0,
              ForjaSpace.s4,
              ForjaSpace.s6,
            ),
            child: Text(
              widget.name.toUpperCase(),
              style: textTheme.displayMedium,
            ),
          ),
          // Expanded le da a la lista todo el alto que sobra. Sin él, un
          // ListView dentro de un Column no sabe cuánto medir y falla
          // ("unbounded height").
          Expanded(
            child: LoadView<(Program, ProgramProgress)>(
              key: ValueKey(_version),
              load: _load,
              builder: (context, data) {
                final (program, progress) = data;
                return _SessionList(
                  program: program,
                  progress: progress,
                  onOpen: _openSession,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({
    required this.program,
    required this.progress,
    required this.onOpen,
  });

  final Program program;
  final ProgramProgress progress;
  final void Function(SessionSummary) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: ForjaSpace.s8),
      itemCount: program.sessions.length,
      // Divider toma color y grosor del dividerTheme (`line`, 1px): las
      // "reglas finas" del sistema de diseño.
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final session = program.sessions[index];
        return _SessionRow(
          session: session,
          done: progress.completedSessionIds.contains(session.id),
          suggested: progress.next?.id == session.id,
          onTap: () => onOpen(session),
        );
      },
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.done,
    required this.suggested,
    required this.onTap,
  });

  final SessionSummary session;
  final bool done;
  final bool suggested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.forja.palette;
    final label = 'FRAGUA ${session.position.toString().padLeft(2, '0')}';

    // La fila sugerida se resalta con accent-soft: el fondo de "fila
    // seleccionada" del sistema de diseño.
    return Material(
      color: suggested ? palette.accentSoft : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ForjaSpace.s4),
          child: Row(
            children: [
              // El check: un cuadrado con borde, relleno de acento si está
              // templada. Ícono de línea, sin redondeos (ver iconografía).
              _Check(done: done),
              const SizedBox(width: ForjaSpace.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: textTheme.labelSmall),
                    const SizedBox(height: ForjaSpace.s1),
                    Text(session.title, style: textTheme.headlineSmall),
                  ],
                ),
              ),
              if (suggested) const ForjaPill('sigue'),
            ],
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final palette = context.forja.palette;
    return Semantics(
      // Para lectores de pantalla: el check no es solo un dibujo.
      label: done ? 'Templada' : 'Sin templar',
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: done ? palette.accent : Colors.transparent,
          border: Border.all(color: palette.stroke, width: 2),
        ),
        child: done
            ? Icon(Icons.check, size: 20, color: palette.onAccent)
            : null,
      ),
    );
  }
}
