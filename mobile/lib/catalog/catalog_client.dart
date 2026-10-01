import 'package:naguan_app/catalog/program.dart';
import 'package:naguan_app/catalog/session.dart';
import 'package:naguan_app/common/api_client.dart';

/// Cliente de la API del catálogo (programas y sesiones). Lo de HTTP lo
/// resuelve [ApiClient]; acá solo se arman los modelos.
///
/// La lista de programas no está acá: sale del progreso del usuario
/// (TrainingClient.fetchProgress), que ya trae nombre y totales.
class CatalogClient {
  const CatalogClient(this._api);

  final ApiClient _api;

  Future<Program> fetchProgram(String slug) async {
    // Uri.encodeComponent escapa el slug por si trae caracteres especiales:
    // nunca concatenar datos crudos en una URL.
    final json = await _api.getJson('/programs/${Uri.encodeComponent(slug)}');
    return Program.fromJson(json as Map<String, dynamic>);
  }

  Future<Session> fetchSession(int id) async {
    final json = await _api.getJson('/sessions/$id');
    return Session.fromJson(json as Map<String, dynamic>);
  }
}
