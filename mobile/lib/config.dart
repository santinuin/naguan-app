/// Configuración de la app.
///
/// Los valores por defecto apuntan al entorno local (`supabase start` y la
/// API Go en la PC). En el emulador Android, la PC host es 10.0.2.2.
///
/// Para otro entorno se pisan al compilar, sin tocar el código:
///   flutter run --dart-define=API_BASE_URL=https://api.ejemplo.com/v1
/// `String.fromEnvironment` lee esos valores en tiempo de compilación (por
/// eso tiene que ser `const`): quedan fijos dentro del APK.
library;

/// URL base de la API Go (versión 1). Los clientes agregan la ruta.
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080/v1',
);

/// URL del proyecto de Supabase (Auth).
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://10.0.2.2:54321',
);

/// Clave "publicable" de Supabase: identifica al proyecto y está pensada
/// para ir dentro de la app (no es un secreto; la seguridad la dan el login
/// y los tokens). Esta es la del entorno local.
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
);
