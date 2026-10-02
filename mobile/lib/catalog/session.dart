/// Una sesión (Fragua) completa, con sus bloques e ítems en orden de
/// ejecución: lo que devuelve `GET /sessions/{id}`.
class Session {
  const Session({
    required this.id,
    required this.title,
    required this.blocks,
    this.description,
  });

  final int id;
  final String title;
  final String? description;
  final List<Block> blocks;

  /// Una copia con otros bloques. Los modelos son inmutables (todos sus
  /// campos son final): "editar" una sesión es armar otra. Ver
  /// session_edits.dart.
  Session copyWith({List<Block>? blocks}) => Session(
    id: id,
    title: title,
    description: description,
    blocks: blocks ?? this.blocks,
  );

  /// El inverso de fromJson: para guardar la sesión en el teléfono (y
  /// poder retomar una Fragua sin red). Un test verifica la ida y vuelta.
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': 'workout',
    'title': title,
    'description': description,
    'blocks': [for (final b in blocks) b.toJson()],
  };

  factory Session.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'title': String title,
        'description': String? description,
        'blocks': List blocks,
      } =>
        Session(
          id: id,
          title: title,
          description: description,
          blocks: [
            for (final b in blocks) Block.fromJson(b as Map<String, dynamic>),
          ],
        ),
      _ => throw FormatException('Sesión con formato inválido: $json'),
    };
  }
}

/// Tipo de bloque. Es un "enhanced enum" de Dart: como un enum de Java, cada
/// valor puede tener campos (acá, el texto que muestra la app) y un
/// constructor const.
enum BlockType {
  rounds('VUELTAS'),
  roundsWithRest('VUELTAS CON PAUSA'),
  tabata('TÁBATA'),
  superset('SUPERSERIE'),
  ladder('ESCALERA'),
  amrap('AMRAP');

  const BlockType(this.label);

  final String label;

  /// El valor de la API ("rounds_with_rest"): el inverso de fromApi.
  String get apiValue => switch (this) {
    rounds => 'rounds',
    roundsWithRest => 'rounds_with_rest',
    tabata => 'tabata',
    superset => 'superset',
    ladder => 'ladder',
    amrap => 'amrap',
  };

  /// Traduce el valor de la API ("rounds_with_rest") al enum.
  static BlockType fromApi(String value) => switch (value) {
    'rounds' => rounds,
    'rounds_with_rest' => roundsWithRest,
    'tabata' => tabata,
    'superset' => superset,
    'ladder' => ladder,
    'amrap' => amrap,
    _ => throw FormatException('Tipo de bloque desconocido: $value'),
  };
}

class Block {
  const Block({
    required this.position,
    required this.type,
    required this.items,
    this.timeCapS,
  });

  final int position;
  final BlockType type;

  /// Solo en los amrap: la duración total del bloque.
  final int? timeCapS;

  /// Todos los ítems del bloque, ordenados por vuelta y posición.
  final List<Item> items;

  Block copyWith({List<Item>? items}) => Block(
    position: position,
    type: type,
    timeCapS: timeCapS,
    items: items ?? this.items,
  );

  /// Los ítems agrupados por vuelta: `rounds[0]` es la vuelta 1. Es un getter
  /// calculado (como un método sin paréntesis): no se guarda, se arma cuando
  /// se pide.
  List<List<Item>> get rounds {
    final byRound = <int, List<Item>>{};
    for (final item in items) {
      // putIfAbsent es el computeIfAbsent de los Map de Java.
      byRound.putIfAbsent(item.round, () => []).add(item);
    }
    // Los Map literales de Dart son LinkedHashMap: mantienen el orden de
    // inserción, que acá es el de las vueltas.
    return byRound.values.toList();
  }

  /// Las vueltas con las consecutivas idénticas agrupadas: un tábata de 8
  /// vueltas iguales es un solo grupo con `count: 8`. Una vuelta que cambia
  /// (otro descanso al final, reps que bajan en una escalera) abre un grupo
  /// nuevo.
  List<RoundGroup> get roundGroups {
    final groups = <RoundGroup>[];
    for (final (index, round) in rounds.indexed) {
      if (groups.isNotEmpty && _sameRound(groups.last.items, round)) {
        // Los RoundGroup son inmutables: se reemplaza el último por uno con
        // una vuelta más, en vez de modificarlo.
        final last = groups.removeLast();
        groups.add(last.withOneMore());
      } else {
        groups.add(RoundGroup(firstRound: index + 1, count: 1, items: round));
      }
    }
    return groups;
  }

  static bool _sameRound(List<Item> a, List<Item> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].signature != b[i].signature) return false;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
    'position': position,
    'type': type.apiValue,
    'time_cap_s': ?timeCapS,
    'items': [for (final i in items) i.toJson()],
  };

  factory Block.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {'position': int position, 'type': String type, 'items': List items} =>
        Block(
          position: position,
          type: BlockType.fromApi(type),
          // time_cap_s es opcional: la API lo omite si no hay tope. Un
          // map pattern exige que la clave exista, así que los campos
          // opcionales se leen aparte con un cast nullable.
          timeCapS: json['time_cap_s'] as int?,
          items: [
            for (final i in items) Item.fromJson(i as Map<String, dynamic>),
          ],
        ),
      _ => throw FormatException('Bloque con formato inválido: $json'),
    };
  }
}

/// Una o varias vueltas consecutivas idénticas de un bloque.
class RoundGroup {
  const RoundGroup({
    required this.firstRound,
    required this.count,
    required this.items,
  });

  /// Número de la primera vuelta del grupo (1, 2, 3...).
  final int firstRound;
  final int count;

  /// Los ítems de una vuelta (todas las del grupo son iguales).
  final List<Item> items;

  int get lastRound => firstRound + count - 1;

  RoundGroup withOneMore() =>
      RoundGroup(firstRound: firstRound, count: count + 1, items: items);
}

enum Side {
  left('IZQUIERDA'),
  right('DERECHA');

  const Side(this.label);

  final String label;
}

/// Un ítem de un bloque: un ejercicio (por tiempo o por reps) o un descanso.
class Item {
  const Item({
    required this.id,
    required this.round,
    required this.position,
    this.exercise,
    this.side,
    this.durationS,
    this.reps,
  });

  /// Identifica el ítem: se manda de vuelta al registrar la Fragua, para
  /// decir qué se hizo en cada ejercicio.
  final int id;
  final int round;
  final int position;

  /// Null en los descansos.
  final ExerciseRef? exercise;
  final Side? side;
  final int? durationS;
  final int? reps;

  bool get isRest => exercise == null;

  /// Una copia con otro ejercicio o con otro objetivo. El `??` deja el valor
  /// actual si no se pasa uno nuevo; por eso un copyWith así no sirve para
  /// poner un campo en null (acá nunca hace falta).
  Item copyWith({ExerciseRef? exercise, int? durationS, int? reps}) => Item(
    id: id,
    round: round,
    position: position,
    exercise: exercise ?? this.exercise,
    side: side,
    durationS: durationS ?? this.durationS,
    reps: reps ?? this.reps,
  );

  /// Lo que define a un ítem dentro de su vuelta, sin la vuelta ni la
  /// posición: sirve para comparar vueltas.
  ///
  /// Es un *record* (una tupla con nombre de tipo implícito). Los records
  /// tienen igualdad estructural incorporada: dos records con los mismos
  /// valores son `==`, sin escribir equals/hashCode (como un `record` de
  /// Java 16+).
  ({String? exercise, Side? side, int? durationS, int? reps}) get signature =>
      (exercise: exercise?.slug, side: side, durationS: durationS, reps: reps);

  Map<String, Object?> toJson() => {
    'id': id,
    'round': round,
    'position': position,
    'kind': isRest ? 'rest' : 'exercise',
    'exercise': ?exercise?.toJson(),
    // .name de un enum es su nombre en el código: Side.left → "left".
    'side': ?side?.name,
    'duration_s': ?durationS,
    'reps': ?reps,
  };

  factory Item.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'id': int id,
        'round': int round,
        'position': int position,
        'kind': String kind,
      } =>
        Item(
          id: id,
          round: round,
          position: position,
          exercise: switch (kind) {
            'rest' => null,
            'exercise' => ExerciseRef.fromJson(
              json['exercise'] as Map<String, dynamic>,
            ),
            _ => throw FormatException('Tipo de ítem desconocido: $kind'),
          },
          // Side.values.byName busca el valor del enum por su nombre
          // ("left" → Side.left), como Enum.valueOf en Java.
          side: switch (json['side']) {
            String side => Side.values.byName(side),
            _ => null,
          },
          durationS: json['duration_s'] as int?,
          reps: json['reps'] as int?,
        ),
      _ => throw FormatException('Ítem con formato inválido: $json'),
    };
  }
}

class ExerciseRef {
  const ExerciseRef({required this.slug, required this.name});

  final String slug;
  final String name;

  Map<String, Object> toJson() => {'slug': slug, 'name': name};

  factory ExerciseRef.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {'slug': String slug, 'name': String name} => ExerciseRef(
        slug: slug,
        name: name,
      ),
      _ => throw FormatException('Ejercicio con formato inválido: $json'),
    };
  }
}
