import 'package:naguan_app/common/local_store.dart';

/// LocalStore en memoria para los tests: un Map en vez del disco.
class MemoryLocalStore implements LocalStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}
