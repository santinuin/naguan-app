import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/auth/lock_gate.dart';
import 'package:naguan_app/theme/forja_theme.dart';

import 'fake_auth_service.dart';
import 'fake_device_lock.dart';

void main() {
  late FakeAuthService auth;
  late FakeDeviceLock lock;
  late DateTime now;

  setUp(() {
    lock = FakeDeviceLock();
    now = DateTime(2026, 10, 2, 12);
  });

  // Como en la app: LockGate en el builder, por encima del Navigator.
  Future<void> pumpApp(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        theme: forjaHierro,
        builder: (context, child) =>
            LockGate(auth: auth, lock: lock, now: () => now, child: child!),
        home: const Scaffold(body: Text('APP')),
      ),
    );
  }

  // Después de lock.answer se usa pumpAndSettle y no pump: el setState de
  // _unlock corre en una microtarea que puede quedar para después del
  // frame, y entonces hace falta un frame más. pumpAndSettle bombea hasta
  // que no quede ninguno pendiente.

  /// Simula ir a segundo plano, que pase [away] y volver.
  Future<void> goAwayFor(WidgetTester tester, Duration away) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(away);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }

  testWidgets('sin sesión no bloquea', (tester) async {
    auth = FakeAuthService();
    await pumpApp(tester);
    await tester.pump(); // el post-frame callback

    expect(find.text('APP'), findsOneWidget);
    expect(lock.calls, 0);
  });

  testWidgets('con sesión guardada pide desbloquear antes de mostrar la app', (
    tester,
  ) async {
    auth = FakeAuthService(signedIn: true);
    await pumpApp(tester);
    await tester.pump();

    // La app ni siquiera se construyó: no se ve ni hace requests.
    expect(find.text('APP'), findsNothing);
    expect(find.text('DESBLOQUEAR'), findsOneWidget);
    expect(lock.isPrompting, isTrue);

    lock.answer(true);
    await tester.pumpAndSettle();

    expect(find.text('APP'), findsOneWidget);
    expect(find.text('DESBLOQUEAR'), findsNothing);
  });

  testWidgets('si se cancela, deja reintentar', (tester) async {
    auth = FakeAuthService(signedIn: true);
    await pumpApp(tester);
    await tester.pump();

    lock.answer(false);
    await tester.pumpAndSettle();

    expect(find.text('No se pudo desbloquear.'), findsOneWidget);
    expect(find.text('APP'), findsNothing);

    await tester.tap(find.text('DESBLOQUEAR'));
    await tester.pump();
    expect(lock.calls, 2);

    lock.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('entrar con contraseña cierra la sesión y abre la app', (
    tester,
  ) async {
    auth = FakeAuthService(signedIn: true);
    await pumpApp(tester);
    await tester.pump();
    lock.answer(false);
    await tester.pumpAndSettle();

    await tester.tap(find.text('ENTRAR CON CONTRASEÑA'));
    await tester.pump();

    expect(auth.isSignedIn, isFalse);
    // En la app real, AuthGate muestra el ingreso.
    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('volver después de un rato bloquea; volver enseguida no', (
    tester,
  ) async {
    auth = FakeAuthService();
    await pumpApp(tester);
    // Entró con contraseña: no se pide huella enseguida.
    auth.signedIn = true;

    await goAwayFor(tester, const Duration(minutes: 1));
    expect(find.text('DESBLOQUEAR'), findsNothing);
    expect(lock.calls, 0);

    await goAwayFor(tester, const Duration(minutes: 5));
    expect(find.text('DESBLOQUEAR'), findsOneWidget);
    // La app sigue construida debajo (una Fragua en curso no se pierde).
    expect(find.text('APP', skipOffstage: false), findsOneWidget);
    expect(lock.calls, 1);

    lock.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('DESBLOQUEAR'), findsNothing);
  });

  testWidgets('el candado tapa también las pantallas abiertas con push', (
    tester,
  ) async {
    auth = FakeAuthService(signedIn: true);
    await pumpApp(tester);
    await tester.pump();
    lock.answer(true);
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('FRAGUA')),
      ),
    );
    await tester.pumpAndSettle();

    await goAwayFor(tester, const Duration(minutes: 10));

    // El candado se dibuja arriba de la Fragua: un toque en el centro le
    // llega al candado, no a la pantalla de abajo.
    expect(find.text('DESBLOQUEAR').hitTestable(), findsOneWidget);
    expect(find.text('FRAGUA').hitTestable(), findsNothing);
  });
}
