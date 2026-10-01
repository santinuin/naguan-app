import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:naguan_app/common/api_client.dart';
import 'package:naguan_app/common/local_store.dart';
import 'package:naguan_app/training/training_client.dart';
import 'package:naguan_app/training/training_models.dart';

/// La cola de Fraguas templadas que todavía no se pudieron registrar (sin
/// señal al terminar). Se guardan en el teléfono y se registran después.
///
/// Reintentar es seguro gracias al client_id de cada Fragua: si el servidor
/// ya la tenía (el POST llegó pero se perdió la respuesta), no la duplica.
class PendingWorkouts {
  const PendingWorkouts(this._store);

  final LocalStore _store;

  static const _key = 'pending_workouts';

  Future<List<NewWorkout>> list() async {
    final raw = await _store.read(_key);
    if (raw == null) return [];
    try {
      return [
        for (final w in jsonDecode(raw) as List)
          NewWorkout.fromJson(w as Map<String, dynamic>),
      ];
    } on Object {
      await _store.remove(_key);
      return [];
    }
  }

  Future<void> add(NewWorkout workout) async {
    final all = await list();
    // Por client_id: si ya estaba en la cola, no se duplica.
    all.removeWhere((w) => w.clientId == workout.clientId);
    await _save([...all, workout]);
  }

  /// Intenta registrar las Fraguas pendientes, en orden. Devuelve cuántas
  /// quedan sin registrar.
  ///
  /// - Registrada (o ya estaba en el servidor): sale de la cola.
  /// - Sin conexión: se corta y se deja todo para la próxima.
  /// - Rechazada por la API (un 4xx, p. ej. una sesión que ya no existe):
  ///   sale de la cola, porque reintentarla daría siempre el mismo error.
  Future<int> flush(TrainingClient training) async {
    final pending = await list();
    final remaining = [...pending];
    for (final workout in pending) {
      try {
        await training.recordWorkout(workout);
        remaining.remove(workout);
      } on ApiException catch (e) {
        final status = e.statusCode;
        if (status == null || status >= 500 || status == 401) break;
        debugPrint('Fragua descartada de la cola (${e.message})');
        remaining.remove(workout);
      }
    }
    await _save(remaining);
    return remaining.length;
  }

  Future<void> _save(List<NewWorkout> workouts) {
    if (workouts.isEmpty) return _store.remove(_key);
    return _store.write(
      _key,
      jsonEncode([for (final w in workouts) w.toJson()]),
    );
  }
}
