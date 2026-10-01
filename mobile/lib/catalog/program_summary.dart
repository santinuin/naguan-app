/// Un programa (Senda) en la lista del catálogo: lo que devuelve
/// `GET /programs` por cada elemento.
class ProgramSummary {
  const ProgramSummary({
    required this.slug,
    required this.name,
    required this.sessionCount,
    this.description,
  });

  final String slug;
  final String name;
  final int sessionCount;

  /// Puede faltar: `String?` es un tipo nullable, y el compilador obliga a
  /// chequear null antes de usarlo (null safety).
  final String? description;

  /// Construye el modelo desde el JSON ya decodificado.
  ///
  /// Usa pattern matching de Dart 3: el `case` verifica a la vez que las
  /// claves existan y que los valores tengan el tipo esperado, y si coincide
  /// los asigna a variables. Si el JSON no tiene la forma esperada, no hay
  /// casteos que exploten a mitad de camino: se lanza un FormatException
  /// claro.
  factory ProgramSummary.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'slug': String slug,
        'name': String name,
        'session_count': int sessionCount,
        'description': String? description,
      } =>
        ProgramSummary(
          slug: slug,
          name: name,
          sessionCount: sessionCount,
          description: description,
        ),
      _ => throw FormatException('Programa con formato inválido: $json'),
    };
  }
}
