import 'package:flutter/material.dart';
import 'package:naguan_app/auth/auth_service.dart';
import 'package:naguan_app/theme/forja_tokens.dart';

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
        // SingleChildScrollView: al abrirse el teclado, el formulario puede
        // no entrar en la pantalla; así se puede scrollear en vez de
        // desbordar.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            ForjaSpace.s4,
            ForjaSpace.s12,
            ForjaSpace.s4,
            ForjaSpace.s8,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('NAGUAN', style: textTheme.displayLarge),
                const SizedBox(height: ForjaSpace.s2),
                const Text('El título se gana. Serie a serie.'),
                const SizedBox(height: ForjaSpace.s12),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'EMAIL'),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  // "Siguiente" en el teclado pasa al campo de contraseña.
                  textInputAction: TextInputAction.next,
                  validator: (value) => (value == null || !value.contains('@'))
                      ? 'Ingresá un email válido.'
                      : null,
                ),
                const SizedBox(height: ForjaSpace.s4),
                TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'CONTRASEÑA'),
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _loading ? null : _submit(),
                  validator: (value) => (value == null || value.isEmpty)
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
                  // onPressed null deshabilita el botón: no se puede tocar
                  // dos veces mientras se espera la respuesta.
                  onPressed: _loading ? null : _submit,
                  child: Text(_loading ? 'ENTRANDO' : 'ENTRAR'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
