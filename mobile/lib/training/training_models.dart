/// Modelos del entrenamiento del usuario: progreso por Senda, Brasa, Mojones
/// y Fraguas templadas. Reflejan las respuestas de `/v1/me/...`.
library;

import 'dart:math';

/// Una Fragua sugerida o referida: posición en la Senda, id y título.
class SessionRef {
  const SessionRef({
    required this.position,
    required this.id,
    required this.title,
  });

  final int position;
  final int id;
  final String title;

  static SessionRef? fromJsonOrNull(Object? json) => switch (json) {
    {'position': int position, 'id': int id, 'title': String title} =>
      SessionRef(position: position, id: id, title: title),
    null => null,
    _ => throw FormatException('Sesión sugerida con formato inválido: $json'),
  };
}

/// El avance del usuario en una Senda.
class ProgramProgress {
  const ProgramProgress({
    required this.slug,
    required this.name,
    required this.completed,
    required this.total,
    this.next,
    this.completedSessionIds = const {},
  });

  final String slug;
  final String name;
  final int completed;
  final int total;

  /// La próxima Fragua sugerida; null si la Senda está completa.
  final SessionRef? next;

  /// Las Fraguas con check. Solo viene en el detalle de una Senda; en la
  /// lista queda vacío. Es un Set: la pregunta es "¿esta tiene check?".
  final Set<int> completedSessionIds;

  double get fraction => total == 0 ? 0 : completed / total;

  factory ProgramProgress.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'program': {'slug': String slug, 'name': String name},
        'completed_sessions': int completed,
        'total_sessions': int total,
      } =>
        ProgramProgress(
          slug: slug,
          name: name,
          completed: completed,
          total: total,
          next: SessionRef.fromJsonOrNull(json['next_session']),
          completedSessionIds: {
            for (final id
                in (json['completed_session_ids'] as List?) ?? const [])
              id as int,
          },
        ),
      _ => throw FormatException('Progreso con formato inválido: $json'),
    };
  }
}

/// La racha del usuario.
class Brasa {
  const Brasa({required this.days, required this.atRisk});

  final int days;

  /// Ya faltó un día hábil y hoy todavía no entrenó: si no entrena, se apaga.
  final bool atRisk;

  bool get isLit => days > 0;
}

class Stats {
  const Stats({required this.brasa, required this.totalWorkouts});

  final Brasa brasa;
  final int totalWorkouts;

  factory Stats.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'brasa': {'days': int days, 'at_risk': bool atRisk},
        'total_workouts': int total,
      } =>
        Stats(
          brasa: Brasa(days: days, atRisk: atRisk),
          totalWorkouts: total,
        ),
      _ => throw FormatException('Stats con formato inválido: $json'),
    };
  }
}

/// Un Mojón: la mejor marca en un ejercicio.
class Record {
  const Record({
    required this.exercise,
    required this.isReps,
    required this.value,
    this.exerciseSlug,
    this.achievedOn,
    this.previous,
  });

  final String exercise;

  /// Para abrir la pantalla del ejercicio. Opcional (como [achievedOn]):
  /// una API anterior no lo manda, y el Mojón se muestra igual.
  final String? exerciseSlug;

  /// true: reps; false: segundos.
  final bool isReps;
  final int value;

  /// El día (en el teléfono) en que se logró la marca.
  final DateTime? achievedOn;

  /// La marca anterior (solo en los Mojones nuevos).
  final int? previous;

  factory Record.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'exercise': String exercise,
        'metric': String metric,
        'value': int value,
      } =>
        Record(
          exercise: exercise,
          exerciseSlug: json['exercise_slug'] as String?,
          isReps: metric == 'reps',
          value: value,
          // tryParse devuelve null (en vez de lanzar, como parse) si el
          // texto no es una fecha; si el campo no vino, `?? ''` le pasa un
          // texto vacío, que tampoco lo es.
          achievedOn: DateTime.tryParse((json['achieved_on'] as String?) ?? ''),
          previous: json['previous'] as int?,
        ),
      _ => throw FormatException('Mojón con formato inválido: $json'),
    };
  }
}

/// Una Fragua templada, como aparece en el historial.
class Workout {
  const Workout({
    required this.id,
    required this.sessionId,
    required this.sessionTitle,
    required this.finishedAt,
    required this.localDate,
    required this.durationS,
    this.programName,
  });

  final int id;
  final int sessionId;
  final String sessionTitle;

  /// La Senda de la Fragua; null si es una sesión suelta.
  final String? programName;
  final DateTime finishedAt;

  /// El día en el teléfono al templarla. Es una fecha sin hora:
  /// `DateTime.parse('2026-10-01')` da la medianoche local de ese día.
  final DateTime localDate;
  final int durationS;

  factory Workout.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'session': {'id': int sessionId, 'title': String title},
        'finished_at': String finishedAt,
        'local_date': String localDate,
        'duration_s': int durationS,
      } =>
        Workout(
          id: id,
          sessionId: sessionId,
          sessionTitle: title,
          // Un patrón también sirve para un campo que puede ser null: si
          // 'program' es un mapa con 'name', se extrae; si no (null), cae
          // en el segundo caso.
          programName: switch (json['program']) {
            {'name': String name} => name,
            _ => null,
          },
          finishedAt: DateTime.parse(finishedAt),
          localDate: DateTime.parse(localDate),
          durationS: durationS,
        ),
      _ => throw FormatException('Fragua templada con formato inválido: $json'),
    };
  }
}

/// Lo que se hizo en un ejercicio de la Fragua.
class ItemResult {
  // {this.exerciseSlug} entre llaves: un parámetro con nombre y opcional,
  // que se pasa como `exerciseSlug: 'dominada'`.
  const ItemResult.reps(this.blockItemId, int this.reps, {this.exerciseSlug})
    : durationS = null;
  const ItemResult.duration(
    this.blockItemId,
    int this.durationS, {
    this.exerciseSlug,
  }) : reps = null;

  final int blockItemId;

  /// El ejercicio que se hizo: puede no ser el del bloque, si antes de
  /// empezar se cambió por una progresión. Null en las Fraguas que una
  /// versión vieja de la app dejó en la cola (la API usa el del bloque).
  final String? exerciseSlug;
  final int? reps;
  final int? durationS;

  Map<String, Object> toJson() => {
    'block_item_id': blockItemId,
    'exercise_slug': ?exerciseSlug,
    'reps': ?reps,
    'duration_s': ?durationS,
  };

  factory ItemResult.fromJson(Map<String, dynamic> json) {
    final slug = json['exercise_slug'] as String?;
    return switch (json) {
      {'block_item_id': int id, 'reps': int reps} => ItemResult.reps(
        id,
        reps,
        exerciseSlug: slug,
      ),
      {'block_item_id': int id, 'duration_s': int s} => ItemResult.duration(
        id,
        s,
        exerciseSlug: slug,
      ),
      _ => throw FormatException('Resultado con formato inválido: $json'),
    };
  }
}

/// Una Fragua terminada, lista para registrar.
class NewWorkout {
  const NewWorkout({
    required this.clientId,
    required this.sessionId,
    required this.startedAt,
    required this.finishedAt,
    required this.items,
    this.amrapRounds = const {},
  });

  /// La clave de idempotencia: un UUID generado en el teléfono, uno por
  /// Fragua. Si el registro se reintenta (sin señal, o se perdió la
  /// respuesta), la API reconoce el mismo id y no la duplica.
  final String clientId;
  final int sessionId;
  final DateTime startedAt;
  final DateTime finishedAt;
  final List<ItemResult> items;

  /// Vueltas completadas en cada AMRAP, por posición del bloque.
  final Map<int, int> amrapRounds;

  Duration get duration => finishedAt.difference(startedAt);

  Map<String, Object> toJson() => {
    'client_id': clientId,
    'session_id': sessionId,
    // La API espera instantes en UTC (RFC 3339).
    'started_at': startedAt.toUtc().toIso8601String(),
    'finished_at': finishedAt.toUtc().toIso8601String(),
    // El día en el teléfono: para la Brasa cuenta el día local.
    'local_date': localDateString(finishedAt),
    'items': [for (final it in items) it.toJson()],
    'amraps': [
      for (final MapEntry(key: position, value: rounds) in amrapRounds.entries)
        {'block_position': position, 'rounds': rounds},
    ],
  };

  /// El inverso de toJson: la cola offline guarda las Fraguas como JSON y
  /// las vuelve a leer para registrarlas.
  factory NewWorkout.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'client_id': String clientId,
        'session_id': int sessionId,
        'started_at': String startedAt,
        'finished_at': String finishedAt,
        'items': List items,
        'amraps': List amraps,
      } =>
        NewWorkout(
          clientId: clientId,
          sessionId: sessionId,
          startedAt: DateTime.parse(startedAt),
          finishedAt: DateTime.parse(finishedAt),
          items: [
            for (final it in items)
              ItemResult.fromJson(it as Map<String, dynamic>),
          ],
          amrapRounds: {
            for (final a in amraps)
              (a as Map<String, dynamic>)['block_position'] as int:
                  a['rounds'] as int,
          },
        ),
      _ => throw FormatException('Fragua guardada con formato inválido: $json'),
    };
  }
}

/// Un UUID versión 4 (aleatorio), con el generador seguro del sistema.
///
/// Son 16 bytes al azar con dos ajustes que marca el estándar (RFC 4122):
/// la versión (4) y la variante. Random.secure() usa la fuente de azar
/// criptográfica del sistema operativo: los ids no se pueden predecir.
String newUuid() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // versión 4
  b[8] = (b[8] & 0x3f) | 0x80; // variante RFC 4122
  String hex(int from, int to) =>
      [for (final x in b.sublist(from, to)) x.toRadixString(16).padLeft(2, '0')]
          .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// Lo que devuelve la API al registrar una Fragua.
class WorkoutResult {
  const WorkoutResult({required this.id, required this.newRecords});

  final int id;
  final List<Record> newRecords;

  factory WorkoutResult.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {'id': int id} => WorkoutResult(
        id: id,
        newRecords: [
          for (final r in (json['new_records'] as List?) ?? const [])
            Record.fromJson(r as Map<String, dynamic>),
        ],
      ),
      _ => throw FormatException('Workout con formato inválido: $json'),
    };
  }
}

/// El día de [t] en la zona horaria del teléfono, como "2026-10-01".
///
/// `toLocal()` convierte un instante a la hora local; de ahí se toman año,
/// mes y día. Es lo que la API llama local_date.
String localDateString(DateTime t) {
  final local = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
