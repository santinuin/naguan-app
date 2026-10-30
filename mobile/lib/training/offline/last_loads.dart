import 'dart:convert';

import 'package:naguan_app/common/local_store.dart';
import 'package:naguan_app/training/training_client.dart';

/// El último peso que usaste en cada ejercicio (por slug), para proponerlo en
/// la próxima serie. Se guarda una copia en el teléfono: una Fragua sin señal
/// también propone el peso de la vez anterior.
class LastLoads {
  const LastLoads(this._store);

  final LocalStore _store;

  static const _key = 'last_loads';

  /// Los pesos guardados en el teléfono (vacío si no hay o están rotos).
  Future<Map<String, double>> cached() async {
    final raw = await _store.read(_key);
    if (raw == null) return {};
    try {
      return {
        for (final MapEntry(:key, :value)
            in (jsonDecode(raw) as Map<String, dynamic>).entries)
          key: (value as num).toDouble(),
      };
    } on Object {
      await _store.remove(_key);
      return {};
    }
  }

  /// Los pesos de la API, guardados para la próxima. Sin señal, devuelve
  /// los guardados: la Fragua no tiene que esperar a la red para empezar.
  Future<Map<String, double>> refresh(TrainingClient client) async {
    try {
      final loads = await client.fetchLastLoads();
      await _store.write(_key, jsonEncode(loads));
      return loads;
    } on Object {
      return cached();
    }
  }

  /// Suma los pesos de una Fragua recién templada (sin esperar a la API: si
  /// se quedó en la cola offline, la próxima ya los propone igual).
  Future<void> remember(Map<String, double> loads) async {
    if (loads.isEmpty) return;
    await _store.write(_key, jsonEncode({...await cached(), ...loads}));
  }
}
