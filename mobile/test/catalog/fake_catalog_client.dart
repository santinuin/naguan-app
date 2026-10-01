import 'dart:async';

import 'package:naguan_app/catalog/catalog_client.dart';
import 'package:naguan_app/catalog/program.dart';
import 'package:naguan_app/catalog/program_summary.dart';
import 'package:naguan_app/catalog/session.dart';

/// Cliente falso del catálogo, compartido por los tests de pantallas.
///
/// Cada llamada devuelve el Future de un Completer nuevo que queda guardado:
/// el test decide cuándo y cómo responde (y puede contar reintentos). Los
/// argumentos recibidos también quedan guardados para verificarlos.
class FakeCatalogClient implements CatalogClient {
  final programsCalls = <Completer<List<ProgramSummary>>>[];
  final programCalls = <Completer<Program>>[];
  final sessionCalls = <Completer<Session>>[];
  final requestedSlugs = <String>[];
  final requestedSessionIds = <int>[];

  @override
  final String baseUrl = 'http://fake';

  @override
  Future<List<ProgramSummary>> fetchPrograms() => _next(programsCalls);

  @override
  Future<Program> fetchProgram(String slug) {
    requestedSlugs.add(slug);
    return _next(programCalls);
  }

  @override
  Future<Session> fetchSession(int id) {
    requestedSessionIds.add(id);
    return _next(sessionCalls);
  }

  Future<T> _next<T>(List<Completer<T>> calls) {
    final completer = Completer<T>();
    calls.add(completer);
    return completer.future;
  }
}
