/// Formatea una duración en segundos como se lee en la app: "45 s", "90 s",
/// "5 min", "2:30".
///
/// Hasta 90 segundos se muestran en segundos (así habla el sistema de
/// diseño: "Enfriá 90 s"); los minutos exactos, en minutos; el resto, como
/// minutos:segundos.
String formatDuration(int seconds) {
  if (seconds <= 90) return '$seconds s';
  // ~/ es la división entera de Dart (el / común siempre devuelve double).
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (rest == 0) return '$minutes min';
  return '$minutes:${rest.toString().padLeft(2, '0')}';
}

/// Formatea repeticiones con el signo de multiplicar: "×10".
String formatReps(int reps) => '×$reps';
