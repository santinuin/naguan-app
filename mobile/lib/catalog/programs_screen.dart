import 'package:flutter/material.dart';
import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/program_screen.dart';
import 'package:naguan_app/common/load_view.dart';
import 'package:naguan_app/theme/forja_pill.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/training/training_services.dart';
import 'package:naguan_app/training/execution/execution_screen.dart';
import 'package:naguan_app/training/history/history_screen.dart';
import 'package:naguan_app/training/history/records_screen.dart';
import 'package:naguan_app/training/offline/active_workout_store.dart';
import 'package:naguan_app/training/training_models.dart';
import 'package:naguan_app/theme/forja_headline.dart';
import 'package:naguan_app/theme/one_line_text.dart';
import 'package:naguan_app/theme/forja_pill_button.dart';

/// La pantalla de inicio: la Brasa y las Sendas con el progreso del usuario.
class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({
    super.key,
    required this.catalog,
    required this.training,
    required this.onSignOut,
  });

  final CatalogClient catalog;
  final TrainingServices training;

  /// Qué hacer al tocar SALIR. La pantalla no sabe de autenticación: recibe
  /// la acción ya armada (un callback), igual que recibe los clientes.
  final VoidCallback onSignOut;

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  /// Sube cada vez que hay que recargar (al volver de una Senda, donde quizá
  /// se templó una Fragua). Ver la key de LoadView en build().
  int _version = 0;

  /// Carga el inicio. Primero intenta registrar las Fraguas que quedaron en
  /// la cola (sin señal al terminarlas): así el progreso y la Brasa ya las
  /// incluyen. Después, en paralelo, el progreso, la Brasa y la Fragua en
  /// curso guardada en el teléfono. `(a, b, c).wait` (Dart 3) espera un
  /// record de Futures y devuelve un record con los resultados.
  Future<_Home> _load() async {
    final training = widget.training;
    final pendingLeft = await training.pending.flush(training.client);
    final (programs, stats, active) = await (
      training.client.fetchProgress(),
      training.client.fetchStats(),
      training.activeWorkout.load(),
    ).wait;
    return (
      programs: programs,
      stats: stats,
      active: active,
      pendingLeft: pendingLeft,
    );
  }

  Future<void> _resume(SavedWorkout saved) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExecutionScreen(
          session: saved.session,
          catalog: widget.catalog,
          training: widget.training,
          restored: saved.snapshot,
        ),
      ),
    );
    if (mounted) setState(() => _version++);
  }

  Future<void> _discardActive() async {
    await widget.training.activeWorkout.clear();
    if (mounted) setState(() => _version++);
  }

  Future<void> _open(ProgramProgress program) async {
    // push devuelve un Future que se completa cuando esa pantalla hace pop:
    // así sabemos que el usuario volvió.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProgramScreen(
          catalog: widget.catalog,
          training: widget.training,
          slug: program.slug,
          name: program.name,
        ),
      ),
    );
    if (mounted) setState(() => _version++);
  }

  /// Abre una pantalla y, al volver, recarga el inicio: desde el historial
  /// se puede volver a templar una Fragua (cambian la Brasa y el progreso).
  Future<void> _push(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LoadView<_Home>(
          // Una key nueva hace que Flutter trate a LoadView como un widget
          // distinto: desmonta el anterior y monta uno nuevo, que vuelve a
          // correr initState (y con él, la carga). Es la forma idiomática de
          // "reiniciar" un widget con estado desde afuera.
          key: ValueKey(_version),
          load: _load,
          // El builder recibe el record y lo desarma con un patrón.
          builder: (context, home) => _ProgramList(
            home: home,
            onOpen: _open,
            onResume: _resume,
            onDiscardActive: _discardActive,
            onSignOut: widget.onSignOut,
            onOpenHistory: () => _push(
              HistoryScreen(catalog: widget.catalog, training: widget.training),
            ),
            onOpenRecords: () => _push(
              RecordsScreen(
                catalog: widget.catalog,
                client: widget.training.client,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que muestra el inicio. Un record con nombres (Dart 3): como un struct
/// liviano, sin declarar una clase.
typedef _Home = ({
  List<ProgramProgress> programs,
  Stats stats,
  SavedWorkout? active,
  int pendingLeft,
});

class _ProgramList extends StatelessWidget {
  const _ProgramList({
    required this.home,
    required this.onOpen,
    required this.onResume,
    required this.onDiscardActive,
    required this.onSignOut,
    required this.onOpenHistory,
    required this.onOpenRecords,
  });

  final _Home home;
  final void Function(ProgramProgress) onOpen;
  final void Function(SavedWorkout) onResume;
  final VoidCallback onDiscardActive;
  final VoidCallback onSignOut;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenRecords;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // Un ListView con children fijos: con pocas Sendas, construirlas todas
    // no cuesta nada, y así se arma fácil una columna con elementos
    // opcionales (la Fragua en curso, la cola).
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ForjaSpace.s4,
        ForjaSpace.s12,
        ForjaSpace.s4,
        ForjaSpace.s8,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La única palabra hero de la pantalla.
            Expanded(
              child: ForjaHeadline('SENDAS', style: textTheme.displayLarge),
            ),
            TextButton(onPressed: onSignOut, child: const OneLineText('SALIR')),
          ],
        ),
        const SizedBox(height: ForjaSpace.s8),
        _BrasaBanner(stats: home.stats),
        const SizedBox(height: ForjaSpace.s6),
        // Los accesos, como pills del mismo ancho que llenan el renglón:
        // fáciles de tocar y sin dejar media pantalla vacía. Sin relleno
        // de acento: el bloque rosa de la pantalla es el de cada Senda.
        Row(
          children: [
            Expanded(
              child: ForjaPillButton(
                label: 'HISTORIAL',
                onPressed: onOpenHistory,
              ),
            ),
            const SizedBox(width: ForjaSpace.s2),
            Expanded(
              child: ForjaPillButton(
                label: 'MOJONES',
                onPressed: onOpenRecords,
              ),
            ),
          ],
        ),
        if (home.active case final active?) ...[
          const SizedBox(height: ForjaSpace.s6),
          _ActiveWorkoutCard(
            saved: active,
            onResume: () => onResume(active),
            onDiscard: onDiscardActive,
          ),
        ],
        if (home.pendingLeft > 0) ...[
          const SizedBox(height: ForjaSpace.s6),
          Text(
            home.pendingLeft == 1
                ? '1 fragua sin registrar: se registra cuando vuelva la señal.'
                : '${home.pendingLeft} fraguas sin registrar: se registran '
                      'cuando vuelva la señal.',
            style: textTheme.bodyLarge?.copyWith(
              color: context.forja.palette.inkMuted,
            ),
          ),
        ],
        for (final program in home.programs) ...[
          const SizedBox(height: ForjaSpace.s6),
          _ProgramCard(program: program, onTap: () => onOpen(program)),
        ],
        const SizedBox(height: ForjaSpace.s8),
        // Los avisos legales: licencias de los paquetes y de las fuentes.
        // showLicensePage es una pantalla que ya trae Flutter.
        Center(
          child: TextButton(
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'FORJA DEL NAGUAN',
            ),
            child: const OneLineText('LICENCIAS'),
          ),
        ),
      ],
    );
  }
}

/// Una Fragua que quedó a medias (el sistema cerró la app): retomarla o
/// descartarla.
class _ActiveWorkoutCard extends StatelessWidget {
  const _ActiveWorkoutCard({
    required this.saved,
    required this.onResume,
    required this.onDiscard,
  });

  final SavedWorkout saved;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(ForjaSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('FRAGUA EN CURSO', style: textTheme.labelSmall),
            const SizedBox(height: ForjaSpace.s1),
            ForjaHeadline(
              saved.session.title.toUpperCase(),
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: ForjaSpace.s4),
            Row(
              children: [
                TextButton(
                  onPressed: onDiscard,
                  child: const OneLineText('DESCARTAR'),
                ),
                const SizedBox(width: ForjaSpace.s2),
                Expanded(
                  child: FilledButton(
                    onPressed: onResume,
                    child: const OneLineText('RETOMAR'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// La Brasa: la racha de días, y el aviso si está por apagarse.
class _BrasaBanner extends StatelessWidget {
  const _BrasaBanner({required this.stats});

  final Stats stats;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final forja = context.forja;
    final brasa = stats.brasa;

    final String message;
    if (!brasa.isLit) {
      message = 'Prendé la brasa: templá una Fragua.';
    } else if (brasa.atRisk) {
      message = 'No la dejes apagar.';
    } else {
      message = '${stats.totalWorkouts} fraguas templadas.';
    }

    // Lo primero que se ve al abrir la app: el número grande (stat, "se
    // lee a un metro") y el mensaje en el estilo de subtítulo, ocupando el
    // ancho.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${brasa.days}',
          style: forja.stat.copyWith(fontSize: 72, height: 1),
        ),
        const SizedBox(width: ForjaSpace.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                brasa.days == 1 ? 'BRASA · DÍA' : 'BRASA · DÍAS',
                style: textTheme.labelSmall?.copyWith(fontSize: 14),
              ),
              const SizedBox(height: ForjaSpace.s1),
              Text(
                message,
                style: brasa.atRisk
                    ? textTheme.headlineSmall?.copyWith(
                        color: forja.palette.accentText,
                      )
                    : textTheme.headlineSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program, required this.onTap});

  final ProgramProgress program;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    // Card toma borde, radio y color del cardTheme de Forja. clipBehavior
    // recorta el efecto del toque (InkWell) a las esquinas redondeadas.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ForjaSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ForjaHeadline(
                program.name.toUpperCase(),
                style: textTheme.titleLarge,
              ),
              // 12 px: con 8 la pill quedaba pegada al título.
              const SizedBox(height: ForjaSpace.s2 + ForjaSpace.s1),
              ForjaPill('${program.completed} / ${program.total} fraguas'),
              const SizedBox(height: ForjaSpace.s4),
              // La barra de progreso: el acento marca lo templado.
              LinearProgressIndicator(
                value: program.fraction,
                minHeight: ForjaSpace.s1 + 2,
                borderRadius: BorderRadius.zero,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
