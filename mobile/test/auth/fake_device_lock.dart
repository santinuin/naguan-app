import 'dart:async';

import 'package:naguan_app/auth/device_lock.dart';

/// DeviceLock falso: cada unlock() queda pendiente hasta que el test lo
/// resuelve con [answer], como si el usuario pusiera (o no) el dedo.
class FakeDeviceLock implements DeviceLock {
  Completer<bool>? _pending;
  int calls = 0;

  bool get isPrompting => _pending != null;

  @override
  Future<bool> unlock() {
    calls++;
    _pending = Completer<bool>();
    return _pending!.future;
  }

  void answer(bool ok) {
    _pending!.complete(ok);
    _pending = null;
  }
}
