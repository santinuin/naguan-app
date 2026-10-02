import 'package:naguan_app/catalog/session.dart';

/// Los ajustes que el usuario le hace a una Fragua antes de empezarla:
/// cambiar las reps o los segundos de un ejercicio, o cambiar el ejercicio
/// por una progresión más fácil o más difícil.
///
/// Son métodos de extensión: se escriben `session.retarget(...)` como si
/// fueran de Session, pero viven en este archivo (como las extension
/// functions de Kotlin). Session sigue siendo solo "lo que manda la API".
///
/// Todos devuelven una Session nueva y no tocan la original: el ajuste es
/// un valor más, y "volver al original" es descartarlo. La sesión ajustada
/// conserva los ids de los ítems, así que el motor la ejecuta, la guarda
/// para retomarla y la registra sin saber que fue ajustada.
extension SessionEdits on Session {
  /// Lo que devuelve el editor de una fila: nuevo objetivo y, quizá, otro
  /// ejercicio. Aplica los dos cambios en el orden correcto: primero el
  /// objetivo, porque retarget encuentra la fila por su ejercicio, y después
  /// del cambio ese ejercicio ya no estaría.
  Session adjust({
    required int blockPosition,
    required Item item,
    required int value,
    required ExerciseRef exercise,
  }) {
    var next = retarget(blockPosition: blockPosition, item: item, value: value);
    final from = item.exercise!.slug;
    if (exercise.slug != from) {
      next = next.swapExercise(
        blockPosition: blockPosition,
        from: from,
        to: exercise,
      );
    }
    return next;
  }

  /// Cambia las reps (o los segundos, según cómo se mida [item]): en todo
  /// el bloque, donde aparezca ese ejercicio con ese mismo objetivo.
  ///
  /// "Con ese mismo objetivo": en una escalera 8-8-5, cambiar el 8 no toca
  /// el 5. "En todo el bloque" (y no solo en la vuelta tocada): los lados de
  /// un unilateral suelen ir en vueltas separadas (derecha en la 1,
  /// izquierda en la 2) y tienen que cambiar juntos.
  Session retarget({
    required int blockPosition,
    required Item item,
    required int value,
  }) {
    final row = _rowKey(item);
    return _replace({
      for (final i in _block(blockPosition).items)
        if (_rowKey(i) == row)
          i.id: item.reps != null
              ? i.copyWith(reps: value)
              : i.copyWith(durationS: value),
    });
  }

  /// Cambia el ejercicio [from] por [to] en todo el bloque: en todas las
  /// vueltas y lados. En una escalera, cada vuelta es una fila distinta, y
  /// cambiarlas una por una sería tedioso.
  Session swapExercise({
    required int blockPosition,
    required String from,
    required ExerciseRef to,
  }) {
    return _replace({
      for (final i in _block(blockPosition).items)
        if (i.exercise?.slug == from) i.id: i.copyWith(exercise: to),
    });
  }

  /// El bloque se busca por posición en ESTA sesión (y no se recibe un
  /// Block): así cada operación parte de los ítems actuales, nunca de los de
  /// una versión anterior de la sesión.
  Block _block(int position) =>
      blocks.firstWhere((b) => b.position == position);

  /// La sesión con los ítems de [changed] (por id) en lugar de los que
  /// tenía.
  Session _replace(Map<int, Item> changed) => copyWith(
    blocks: [
      for (final b in blocks)
        b.copyWith(items: [for (final i in b.items) changed[i.id] ?? i]),
    ],
  );
}

/// Lo que identifica qué ítems se ajustan juntos: el ejercicio y su
/// objetivo, sin el lado ni la vuelta. Un record, para
/// compararlo con `==` sin escribir equals.
({String? exercise, int? reps, int? durationS}) _rowKey(Item i) =>
    (exercise: i.exercise?.slug, reps: i.reps, durationS: i.durationS);
