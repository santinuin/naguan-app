import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/auth/secure_session_storage.dart';

import '../common/memory_local_store.dart';

void main() {
  test('guarda, lee y borra la sesión en el LocalStore', () async {
    final store = MemoryLocalStore();
    final storage = SecureSessionStorage(store);
    await storage.initialize();

    expect(await storage.hasAccessToken(), isFalse);

    await storage.persistSession('{"refresh_token":"r"}');
    expect(await storage.hasAccessToken(), isTrue);
    expect(await storage.accessToken(), '{"refresh_token":"r"}');

    await storage.removePersistedSession();
    expect(await storage.hasAccessToken(), isFalse);
    expect(store.values, isEmpty);
  });
}
