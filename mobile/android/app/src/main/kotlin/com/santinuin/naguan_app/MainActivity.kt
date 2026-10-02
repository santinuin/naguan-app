package com.santinuin.naguan_app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity y no FlutterActivity: el diálogo de huella de
// Android (BiometricPrompt, que usa local_auth) se muestra como un Fragment,
// y necesita una Activity que los soporte.
class MainActivity : FlutterFragmentActivity()
