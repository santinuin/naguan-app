import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naguan_app/auth/auth_gate.dart';
import 'package:naguan_app/auth/login_screen.dart';
import 'package:naguan_app/theme/forja_theme.dart';

import 'fake_auth_service.dart';

Future<void> pumpGate(WidgetTester tester, FakeAuthService auth) {
  return tester.pumpWidget(
    MaterialApp(
      theme: forjaHierro,
      home: AuthGate(
        auth: auth,
        signedIn: (_) => Scaffold(
          body: TextButton(onPressed: auth.signOut, child: const Text('APP')),
        ),
      ),
    ),
  );
}

void main() {
  // Son dos tests y no uno con dos pumpWidget: si en el mismo test se monta
  // otro AuthGate en la misma posición, Flutter reutiliza el State del
  // anterior (mismo tipo, mismo lugar en el árbol) y no vuelve a correr
  // initState. Cada test arranca con un árbol vacío.
  testWidgets('sin sesión muestra el ingreso', (tester) async {
    await pumpGate(tester, FakeAuthService());

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('con sesión muestra la app', (tester) async {
    await pumpGate(tester, FakeAuthService(signedIn: true));

    expect(find.text('APP'), findsOneWidget);
  });

  testWidgets('entrar y salir cambia la pantalla sola', (tester) async {
    final auth = FakeAuthService();
    await pumpGate(tester, auth);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      ' yo@naguan.local ',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'secreta');
    await tester.tap(find.text('ENTRAR'));
    await tester.pump(); // procesa el signIn y el evento del stream

    // El email llega sin espacios; la pantalla cambió sin navegar a mano.
    expect(auth.signInCalls, [('yo@naguan.local', 'secreta')]);
    expect(find.text('APP'), findsOneWidget);

    await tester.tap(find.text('APP')); // signOut
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('valida el formulario antes de llamar al servidor', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await pumpGate(tester, auth);

    await tester.tap(find.text('ENTRAR'));
    await tester.pump();

    expect(find.text('Ingresá un email válido.'), findsOneWidget);
    expect(find.text('Ingresá tu contraseña.'), findsOneWidget);
    expect(auth.signInCalls, isEmpty);
  });

  testWidgets('muestra el error del ingreso', (tester) async {
    final auth = FakeAuthService()
      ..failWith = 'Email o contraseña incorrectos.';
    await pumpGate(tester, auth);

    await tester.enterText(find.byType(TextFormField).at(0), 'yo@naguan.local');
    await tester.enterText(find.byType(TextFormField).at(1), 'mal');
    await tester.tap(find.text('ENTRAR'));
    await tester.pump();

    expect(find.text('Email o contraseña incorrectos.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    // El botón vuelve a estar habilitado para reintentar.
    expect(find.text('ENTRAR'), findsOneWidget);
  });
}
