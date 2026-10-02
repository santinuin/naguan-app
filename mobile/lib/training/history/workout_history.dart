import 'package:flutter/foundation.dart';
import 'package:naguan_app/training/training_client.dart';
import 'package:naguan_app/training/training_models.dart';

/// El historial de Fraguas templadas, cargado de a páginas.
///
/// Es un ChangeNotifier, como WorkoutRunner: la lógica (qué página pedir,
/// cuándo no pedir más, qué pasa ante un error) vive acá y se testea sin
/// widgets; la pantalla solo lo dibuja con un ListenableBuilder y le avisa
/// cuando el scroll se acerca al final.
///
/// LoadView no alcanza acá: carga un dato una vez, y esto es una lista que
/// crece y puede fallar a la mitad (con 60 Fraguas ya en pantalla, un error
/// en la página siguiente no tiene que borrarlas).
class WorkoutHistory extends ChangeNotifier {
  WorkoutHistory(this._client, {this.pageSize = 20});

  final TrainingClient _client;
  final int pageSize;

  final _workouts = <Workout>[];
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;
  bool _disposed = false;

  /// Las Fraguas cargadas hasta ahora. Se expone una vista de solo lectura:
  /// la pantalla puede leerla pero no agregarle nada (como
  /// Collections.unmodifiableList de Java).
  List<Workout> get workouts => List.unmodifiable(_workouts);

  /// Hay una página en camino.
  bool get loading => _loading;

  /// Quedan Fraguas más viejas por pedir.
  bool get hasMore => _hasMore;

  /// La última página falló; [loadMore] la reintenta.
  bool get failed => _failed;

  /// Pide la página siguiente. Se puede llamar de más (el scroll la llama
  /// muchas veces seguidas): si ya hay una en camino o no quedan, no hace
  /// nada.
  Future<void> loadMore() async {
    if (_loading || !_hasMore) return;
    _loading = true;
    _failed = false;
    notifyListeners();

    try {
      // lastOrNull: el último elemento, o null si la lista está vacía (la
      // primera página no lleva cursor).
      final page = await _client.fetchWorkouts(
        before: _workouts.lastOrNull?.id,
        limit: pageSize,
      );
      _workouts.addAll(page);
      // Una página incompleta es la última. Si la última justo viene llena,
      // se pide una más que llega vacía: un request de más, a cambio de no
      // necesitar un total en la API.
      _hasMore = page.length == pageSize;
    } on Exception {
      // `on Exception` atrapa las fallas esperables (sin red, la API
      // responde un error, JSON inválido). Los Error de Dart (un null
      // inesperado, un índice fuera de rango) son bugs: se dejan pasar para
      // que se vean, en vez de mostrarlos como "sin señal".
      _failed = true;
    } finally {
      _loading = false;
      // La pantalla pudo cerrarse mientras esperábamos la respuesta. Avisar
      // a un ChangeNotifier ya descartado es un error en Flutter.
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
