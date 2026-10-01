/// Un programa (Senda) con sus sesiones (Fraguas) en orden: lo que devuelve
/// `GET /programs/{slug}`.
class Program {
  const Program({
    required this.slug,
    required this.name,
    required this.sessions,
    this.description,
  });

  final String slug;
  final String name;
  final String? description;
  final List<SessionSummary> sessions;

  factory Program.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {
        'slug': String slug,
        'name': String name,
        'description': String? description,
        // `List sessions` verifica que sea una lista; cada elemento se
        // convierte después con SessionSummary.fromJson.
        'sessions': List sessions,
      } =>
        Program(
          slug: slug,
          name: name,
          description: description,
          sessions: [
            for (final s in sessions)
              SessionSummary.fromJson(s as Map<String, dynamic>),
          ],
        ),
      _ => throw FormatException('Programa con formato inválido: $json'),
    };
  }
}

/// Una sesión dentro de la lista de un programa.
class SessionSummary {
  const SessionSummary({
    required this.position,
    required this.id,
    required this.title,
  });

  /// Posición dentro del programa: 1, 2, 3...
  final int position;
  final int id;
  final String title;

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    return switch (json) {
      {'position': int position, 'id': int id, 'title': String title} =>
        SessionSummary(position: position, id: id, title: title),
      _ => throw FormatException('Sesión con formato inválido: $json'),
    };
  }
}
