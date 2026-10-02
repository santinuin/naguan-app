import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/session_screen.dart';
import 'package:naguan_app/common/load_view.dart';
import 'package:naguan_app/theme/forja_pill.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/training/history/dates.dart';
import 'package:naguan_app/training/history/workout_history.dart';
import 'package:naguan_app/training/training_models.dart';
import 'package:naguan_app/training/training_services.dart';

/// El historial: las Fraguas templadas, de la más reciente a la más vieja,
/// agrupadas por mes. Se cargan de a páginas a medida que se baja.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.catalog,
    required this.training,
  });

  final CatalogClient catalog;
  final TrainingServices training;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// Cuántos píxeles antes del final se pide la página siguiente: así llega
  /// antes de que el usuario toque fondo y el scroll no se corta.
  static const _prefetchExtent = 600.0;

  /// No es final: al volver de una Fragua se descarta y se crea otro (ver
  /// _openSession).
  late WorkoutHistory _history;

  /// Un ScrollController expone la posición del scroll y avisa cuando
  /// cambia. Lo crea y lo descarta este State: tiene que vivir lo mismo que
  /// la pantalla, no lo mismo que un build().
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _history = WorkoutHistory(widget.training.client)..loadMore();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    // Lo que el State crea, el State lo descarta: si no, el controlador
    // seguiría avisando a una pantalla que ya no existe.
    _scroll.dispose();
    _history.dispose();
    super.dispose();
  }

  void _onScroll() {
    // extentAfter: cuánto contenido queda debajo de lo visible.
    if (_scroll.position.extentAfter < _prefetchExtent) {
      _history.loadMore(); // si ya hay una en camino, no hace nada
    }
  }

  /// Abre la Fragua (para verla o volver a templarla). Al volver, el
  /// historial puede estar viejo (quizá se templó una): se arranca de cero
  /// con un controlador nuevo. El viejo se descarta; si tenía una página en
  /// camino, su respuesta se ignora (ver `_disposed` en WorkoutHistory).
  Future<void> _openSession(Workout workout) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionScreen(
          catalog: widget.catalog,
          training: widget.training,
          id: workout.sessionId,
          label: workout.programName?.toUpperCase() ?? 'FRAGUA',
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _history.dispose();
      _history = WorkoutHistory(widget.training.client)..loadMore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(),
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
            child: Text('HISTORIAL', style: textTheme.displayMedium),
          ),
          Expanded(
            // ListenableBuilder vuelve a correr builder cada vez que el
            // historial llama a notifyListeners (llegó una página, falló,
            // empezó a cargar). Solo se reconstruye lo de adentro.
            child: ListenableBuilder(
              listenable: _history,
              builder: (context, _) => _body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final history = _history;
    final workouts = history.workouts;

    // Sin nada cargado todavía, los tres estados ocupan toda la pantalla.
    if (workouts.isEmpty) {
      if (history.failed) return ErrorView(onRetry: history.loadMore);
      if (history.hasMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return const _EmptyHistory();
    }

    // ListView.builder construye solo las filas visibles (y un margen), a
    // medida que se scrollea: con cientos de Fraguas no arma cientos de
    // widgets de entrada. Es el RecyclerView de Android.
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: ForjaSpace.s8),
      // Una fila más que las Fraguas: el pie (cargando, reintentar o nada).
      itemCount: workouts.length + 1,
      itemBuilder: (context, index) {
        if (index == workouts.length) {
          return _Footer(history: history);
        }
        final workout = workouts[index];
        // El encabezado del mes va arriba de la primera Fragua de cada
        // mes: la que no comparte mes con la anterior.
        final newMonth =
            index == 0 ||
            !sameMonth(workouts[index - 1].localDate, workout.localDate);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newMonth) _MonthHeader(date: workout.localDate),
            _WorkoutRow(workout: workout, onTap: () => _openSession(workout)),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(ForjaSpace.s4),
      child: Text(
        'Todavía no templaste ninguna Fragua. Elegí una Senda y arrancá.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ForjaSpace.s4,
        ForjaSpace.s6,
        ForjaSpace.s4,
        ForjaSpace.s2,
      ),
      child: Text(
        formatMonth(date),
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _WorkoutRow extends StatelessWidget {
  const _WorkoutRow({required this.workout, required this.onTap});

  final Workout workout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final day = workout.localDate;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(ForjaSpace.s4),
        child: Row(
          children: [
            // El día, como en una hoja de calendario: número grande y el
            // día de la semana abajo. Ancho fijo para que los títulos de
            // todas las filas arranquen a la misma altura.
            SizedBox(
              width: 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    day.day.toString().padLeft(2, '0'),
                    style: textTheme.titleLarge,
                  ),
                  Text(weekdayShort(day), style: textTheme.labelSmall),
                ],
              ),
            ),
            const SizedBox(width: ForjaSpace.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (workout.programName case final program?)
                    Text(program.toUpperCase(), style: textTheme.labelSmall),
                  const SizedBox(height: ForjaSpace.s1),
                  Text(workout.sessionTitle, style: textTheme.headlineSmall),
                ],
              ),
            ),
            const SizedBox(width: ForjaSpace.s2),
            ForjaPill(_formatLength(workout.durationS)),
          ],
        ),
      ),
    );
  }
}

/// La duración de una Fragua: en minutos ("32 min"), o en segundos si no
/// llegó a uno. formatDuration (la de los ejercicios) no sirve: escribiría
/// 32 minutos como "32:15", que se lee como una hora.
String _formatLength(int seconds) =>
    seconds < 60 ? '$seconds s' : '${seconds ~/ 60} min';

/// El pie de la lista: un indicador mientras llega la página siguiente, o
/// el botón para reintentarla si falló. Con todo cargado, nada.
class _Footer extends StatelessWidget {
  const _Footer({required this.history});

  final WorkoutHistory history;

  @override
  Widget build(BuildContext context) {
    if (history.failed) {
      return Padding(
        padding: const EdgeInsets.all(ForjaSpace.s4),
        child: Column(
          children: [
            Text(
              'No se pudieron traer las anteriores.',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: context.forja.palette.inkMuted),
            ),
            TextButton(
              onPressed: history.loadMore,
              child: const Text('REINTENTAR'),
            ),
          ],
        ),
      );
    }
    if (history.loading) {
      return const Padding(
        padding: EdgeInsets.all(ForjaSpace.s6),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox.shrink();
  }
}
