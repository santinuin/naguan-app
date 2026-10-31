import 'package:naguan_app/catalog/session.dart';

/// Formatea una duración en segundos como se lee en la app: "45″", "90″",
/// "5′", "2′30″".
///
/// La notación de las planillas de entrenamiento: ″ (doble prima, U+2033)
/// para los segundos y ′ (prima, U+2032) para los minutos. Son los signos
/// tipográficos, no las comillas rectas (" y ') del teclado. Las fuentes
/// empaquetadas los incluyen. Al no tener mayúscula ni minúscula, se leen
/// igual dentro de una pill, que pasa todo a MAYÚSCULAS (con "s" quedaba
/// "32 S").
///
/// Hasta 90 segundos se muestran en segundos (un descanso de "90″" se lee
/// mejor que "1′30″"); los minutos exactos, en minutos; el resto, en
/// minutos y segundos.
String formatDuration(int seconds) {
  if (seconds <= 90) return '$seconds″';
  // ~/ es la división entera de Dart (el / común siempre devuelve double).
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (rest == 0) return '$minutes′';
  return '$minutes′${rest.toString().padLeft(2, '0')}″';
}

/// Formatea repeticiones con el signo de multiplicar: "×10".
String formatReps(int reps) => '×$reps';

/// Formatea un peso en kilos como se escribe acá: con coma decimal y sin
/// ceros de más. "100 kg", "102,5 kg", "1,25 kg".
String formatKg(double kg) => '${formatKgNumber(kg)} kg';

/// El número de [formatKg], sin la unidad (para mostrarlo en grande).
String formatKgNumber(double kg) {
  // toStringAsFixed(2) da "102.50"; se sacan los ceros y el punto que
  // sobran, y el punto decimal pasa a coma.
  var text = kg.toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return text.replaceAll('.', ',');
}

/// La cifra de un ítem como se lee en la app: "×10", "×5-8" (un rango),
/// "×máx" (todas las que puedas), "45″", "máx" (el máximo tiempo posible).
String formatTarget(Item item) => switch (item) {
  Item(open: true, reps: _?) => '×máx',
  Item(open: true, durationS: _?) => 'máx',
  Item(:final reps?, :final repsMin?) => '×$repsMin-$reps',
  Item(:final reps?) => formatReps(reps),
  Item(:final durationS?) => formatDuration(durationS),
  _ => '',
};
