/// Fechas como se leen en la app: "MIÉ", "1 OCT 2026", "OCTUBRE 2026".
///
/// Escrito a mano en vez de usar el paquete `intl`: son tres tablas y para el
/// castellano `intl` pide además cargar los datos del idioma
/// (`initializeDateFormatting`) antes de formatear. Si la app algún día
/// tuviera más de un idioma, ahí sí conviene `intl`.
library;

// DateTime.weekday va de 1 (lunes) a 7 (domingo), y month de 1 a 12: de ahí
// el - 1 para indexar las listas.
const _weekdays = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];
const _months = [
  'ENERO',
  'FEBRERO',
  'MARZO',
  'ABRIL',
  'MAYO',
  'JUNIO',
  'JULIO',
  'AGOSTO',
  'SEPTIEMBRE',
  'OCTUBRE',
  'NOVIEMBRE',
  'DICIEMBRE',
];

/// El día de la semana abreviado: "MIÉ".
String weekdayShort(DateTime d) => _weekdays[d.weekday - 1];

/// "1 OCT 2026": el mes abreviado a tres letras.
String formatDate(DateTime d) =>
    '${d.day} ${_months[d.month - 1].substring(0, 3)} ${d.year}';

/// "OCTUBRE 2026": el encabezado de cada mes en el historial.
String formatMonth(DateTime d) => '${_months[d.month - 1]} ${d.year}';

/// Si dos fechas caen en el mismo mes (para agrupar el historial).
bool sameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;
