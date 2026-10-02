import 'package:flutter/material.dart';
import 'package:naguan_app/auth/auth_service.dart';
import 'package:naguan_app/theme/forja_theme.dart';
import 'package:naguan_app/theme/forja_tokens.dart';
import 'package:naguan_app/theme/forja_wordmark.dart';
import 'package:naguan_app/theme/one_line_text.dart';

/// Ingreso con email y contraseña.
///
/// No navega a ningún lado al entrar: AuthGate escucha el estado de la
/// sesión y cambia de pantalla solo. Esta pantalla solo pide entrar.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// La "llave" del formulario: da acceso a su estado para validarlo todo
  /// junto (`_formKey.currentState!.validate()`).
  final _formKey = GlobalKey<FormState>();

  /// Los controllers guardan el texto de cada campo. Son recursos: hay que
  /// liberarlos en dispose(), o quedan escuchando después de cerrar la
  /// pantalla (una pérdida de memoria).
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // validate() corre el validator de cada campo y muestra los errores.
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.auth.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
      // Éxito: no hay nada que hacer acá. AuthGate recibe el evento del
      // stream y reemplaza esta pantalla.
    } on AuthFailure catch (e) {
      // Después de un await, la pantalla pudo haberse cerrado: `mounted`
      // dice si el State sigue en el árbol. setState sobre un State
      // desmontado es un error.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        // La marca arriba y el formulario abajo, a mano del pulgar (como
        // la pantalla de bloqueo). Pero con el teclado abierto el
        // formulario tiene que poder subir: hace falta scroll.
        //
        // El problema: dentro de un SingleChildScrollView el alto es
        // infinito, y un Spacer no tiene "espacio sobrante" que ocupar. La
        // receta:
        // - LayoutBuilder da el alto real de la pantalla;
        // - ConstrainedBox(minHeight) hace que el contenido mida AL MENOS
        //   eso (si es más alto, scrollea);
        // - una Column con alto máximo infinito mide lo que su contenido o
        //   el mínimo, lo que sea mayor; MainAxisAlignment.center pone sus
        //   hijos en el medio y reparte lo que sobra arriba y abajo. La
        //   marca y el formulario van juntos, como un solo bloque, con una
        //   separación fija entre ellos.
        //
        // (La receta que más se ve en internet usa IntrinsicHeight + Spacer,
        // pero IntrinsicHeight le pregunta a cada hijo su alto sin hacer el
        // layout, y la marca, que se escala para llenar el ancho, responde
        // con su alto sin escalar: la Column desbordaba.)
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            // Simétrico arriba y abajo: el bloque va centrado.
            padding: const EdgeInsets.symmetric(
              horizontal: ForjaSpace.s4,
              vertical: ForjaSpace.s8,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // El padding vertical del scroll se descuenta: si no, el
                // contenido mediría la pantalla MÁS el padding y siempre
                // scrollearía un poco.
                minHeight: constraints.maxHeight - 2 * ForjaSpace.s8,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ForjaWordmark(),
                        const SizedBox(height: ForjaSpace.s4),
                        // La tagline, como en la portada del sistema de
                        // diseño: en texto secundario debajo de la marca.
                        Text(
                          'El título se gana. Serie a serie.',
                          style: textTheme.bodyLarge?.copyWith(
                            color: context.forja.palette.inkMuted,
                          ),
                        ),
                      ],
                    ),
                    // El formulario, a una distancia fija de la marca.
                    Padding(
                      padding: const EdgeInsets.only(top: ForjaSpace.s12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _email,
                            decoration: const InputDecoration(
                              labelText: 'EMAIL',
                            ),
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email],
                            // "Siguiente" en el teclado pasa a la contraseña.
                            textInputAction: TextInputAction.next,
                            validator: (value) =>
                                (value == null || !value.contains('@'))
                                ? 'Ingresá un email válido.'
                                : null,
                          ),
                          const SizedBox(height: ForjaSpace.s4),
                          TextFormField(
                            controller: _password,
                            decoration: const InputDecoration(
                              labelText: 'CONTRASEÑA',
                            ),
                            obscureText: true,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) =>
                                _loading ? null : _submit(),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                ? 'Ingresá tu contraseña.'
                                : null,
                          ),
                          if (_error case final error?) ...[
                            const SizedBox(height: ForjaSpace.s4),
                            Text(
                              error,
                              style: textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ],
                          const SizedBox(height: ForjaSpace.s6),
                          FilledButton(
                            // onPressed null deshabilita el botón: no se puede
                            // tocar dos veces mientras se espera la respuesta.
                            onPressed: _loading ? null : _submit,
                            child: OneLineText(
                              _loading ? 'ENTRANDO' : 'ENTRAR',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
