import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/format.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/training/training_models.dart';
import 'package:naguan_app/theme/forja_headline.dart';

/// El resumen de una Fragua templada: duración, golpes y los Mojones
/// superados.
class TempladoScreen extends StatelessWidget {
  const TempladoScreen({
    super.key,
    required this.session,
    required this.workout,
    required this.result,
    required this.exercises,
  });

  final Session session;
  final NewWorkout workout;

  /// La respuesta de la API; null si se encoló para registrarla después
  /// (sin señal al terminar).
  final WorkoutResult? result;

  /// Ejercicios registrados (los golpes).
  final int exercises;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final minutes = workout.duration.inMinutes;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            ForjaSpace.s4,
            ForjaSpace.s12,
            ForjaSpace.s4,
            ForjaSpace.s8,
          ),
          children: [
            // FittedBox con scaleDown achica el texto si no entra en el
            // ancho (y lo deja igual si entra): una palabra hero nunca se
            // corta a la mitad, regla del sistema de diseño.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('TEMPLADO.', style: textTheme.displayLarge),
            ),
            const SizedBox(height: ForjaSpace.s2),
            Text(session.title.toUpperCase(), style: textTheme.labelSmall),
            const SizedBox(height: ForjaSpace.s8),
            Row(
              children: [
                Expanded(
                  child: _Stat(value: '$minutes', label: 'MINUTOS'),
                ),
                Expanded(
                  child: _Stat(value: '$exercises', label: 'GOLPES'),
                ),
              ],
            ),
            if (result == null) ...[
              const SizedBox(height: ForjaSpace.s6),
              const Text(
                'Sin señal: la Fragua quedó guardada en el teléfono y se '
                'registra cuando vuelva la conexión.',
              ),
            ],
            for (final record in result?.newRecords ?? const <Record>[]) ...[
              const SizedBox(height: ForjaSpace.s6),
              _RecordChip(record: record),
            ],
            const SizedBox(height: ForjaSpace.s12),
            FilledButton(
              // pop vuelve a la sesión: la ejecución ya no está en la pila
              // (se reemplazó por esta pantalla).
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('LISTO'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: context.forja.stat),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// "NUEVO MOJÓN": el chip `signal` del sistema de diseño (amarillo, con
/// texto en tinta). Siempre con palabras y números: nunca solo el color.
class _RecordChip extends StatelessWidget {
  const _RecordChip({required this.record});

  final Record record;

  @override
  Widget build(BuildContext context) {
    final palette = context.forja.palette;
    final textTheme = Theme.of(context).textTheme;
    String fmt(int v) => record.isReps ? formatReps(v) : formatDuration(v);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.signal,
        border: Border.all(color: palette.stroke, width: ForjaBorder.heavy),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ForjaSpace.s4),
        child: DefaultTextStyle.merge(
          // Todo el texto del chip en tinta (on-accent): nunca blanco sobre
          // el amarillo.
          style: TextStyle(color: palette.onAccent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NUEVO MOJÓN',
                style: textTheme.labelSmall?.copyWith(color: palette.onAccent),
              ),
              const SizedBox(height: ForjaSpace.s1),
              ForjaHeadline(
                record.exercise.toUpperCase(),
                style: textTheme.titleLarge?.copyWith(color: palette.onAccent),
              ),
              const SizedBox(height: ForjaSpace.s1),
              Text(
                '${fmt(record.value)}  (antes ${fmt(record.previous ?? 0)})',
                style: context.forja.bodyStrong.copyWith(
                  color: palette.onAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
