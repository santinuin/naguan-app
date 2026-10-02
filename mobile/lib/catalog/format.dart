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
