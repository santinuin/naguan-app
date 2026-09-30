# Mobile (Flutter)

App móvil de calistenia. Ver `/CLAUDE.md` en la raíz del repo para el contexto completo
de arquitectura y decisiones.

- **Paquete Dart:** `workout_app` (nombre técnico provisorio; renombrarlo es fácil).
- **applicationId Android:** `com.santinuin.workout_app` (este es más incómodo de cambiar
  una vez que hay instalaciones, así que conviene no tocarlo a la ligera).
- **Plataformas:** solo Android. iOS queda pendiente (requiere Apple Developer, USD 99/año).

## Estado

Esqueleto generado con `flutter create`. Todavía es la app de ejemplo (el contador).

## Entorno de desarrollo

Versiones con las que se armó el proyecto: Flutter 3.47.5 / Dart 3.13.4.

| Pieza | Dónde vive | Para qué |
|---|---|---|
| Flutter SDK | `~/development/flutter` | Framework + herramienta `flutter`. Incluye Dart |
| Android SDK | `~/Android/Sdk` | Compilar para Android, `adb`, emulador |
| Imagen del emulador | `~/Android/Sdk/system-images` | El "sistema operativo" del teléfono virtual |
| AVD `pixel8` | `~/.android/avd` | El teléfono virtual en sí (config + disco) |

Variables de entorno (en `~/.profile`):

```bash
export PATH="$PATH:$HOME/development/flutter/bin"
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
```

Verificar que todo está bien:

```bash
flutter doctor -v
```

Tiene que estar en ✓ **Flutter** y **Android toolchain**. Los ✗ de *Linux toolchain* y
*Chrome* se ignoran: son para desktop/web y no los usamos.

## Levantar el emulador

```bash
emulator -list-avds          # qué emuladores existen
emulator -avd pixel8 &       # arrancarlo; el & lo deja en segundo plano
adb devices                  # cuando aparece "emulator-5554  device", ya booteó
flutter devices              # Flutter también lo tiene que ver
```

- El primer arranque tarda más de un minuto; los siguientes son más rápidos.
- `offline` en `adb devices` significa que todavía está arrancando: esperar unos segundos.
- Si la ventana sale negra o con artefactos gráficos (la notebook tiene dos GPU), arrancar con
  render por software: `emulator -avd pixel8 -gpu swiftshader_indirect`.
- Cerrar el emulador: cerrar la ventana, o `adb emu kill`.

### Crear el emulador desde cero

Se hizo por línea de comandos porque el Device Manager de Android Studio se colgaba en
esta máquina (Skiko no puede crear el contexto OpenGL con las dos GPU bajo X11).

```bash
sdkmanager "system-images;android-36;google_apis_playstore;x86_64"
avdmanager create avd -n pixel8 \
  -k "system-images;android-36;google_apis_playstore;x86_64" -d pixel_8
```

- `x86_64` porque, con KVM, corre nativo en la CPU. Una imagen ARM sería mucho más lenta.
- `google_apis_playstore` trae Google Play Services.
- `sdkmanager` está deprecado a favor de `android sdk`, pero sigue funcionando y redirige.

## Correr la app

```bash
cd mobile
flutter run                  # compila, instala y abre la app en el dispositivo
```

⚠️ El **primer** `flutter run` tarda varios minutos (Gradle descarga y compila todo).
Los siguientes son rápidos.

Con la app corriendo, en esa misma terminal:

| Tecla | Acción | Cuándo usarla |
|---|---|---|
| `r` | **Hot reload**: inyecta el código nuevo y **conserva el estado** | Cambios de UI. Lo que más vas a usar |
| `R` | **Hot restart**: reinicia la app y **pierde el estado** | Cambios en `main()`, estado inicial o variables globales |
| `p` | Dibuja la grilla de layout | Entender por qué algo quedó mal acomodado |
| `q` | Salir | |
| `h` | Lista todas las teclas | |

Regla práctica: si un cambio no se ve con `r`, probá `R`. Si tampoco, detené `flutter run` y
volvé a correrlo (cambios en `pubspec.yaml` o en `android/`).

Probar en un **teléfono real** (conviene hacerlo seguido: rendimiento y tacto son distintos):

1. En el teléfono: Ajustes → Acerca del teléfono → tocar 7 veces *Número de compilación*.
2. Ajustes → Opciones de desarrollador → activar *Depuración USB*.
3. Conectarlo por USB y aceptar el diálogo de huella RSA.
4. `flutter devices` lo lista; `flutter run -d <id>` elige el dispositivo si hay más de uno.

## Comandos útiles

```bash
# Diagnóstico
flutter doctor -v            # estado de todo el entorno
flutter devices              # dispositivos conectados / emuladores
flutter --version            # versión de Flutter y Dart

# Calidad de código
flutter analyze              # análisis estático (el "staticcheck" de Dart)
dart format lib test         # formatea (el "gofmt" de Dart)
flutter test                 # corre los tests
flutter test --coverage      # idem, con cobertura

# Dependencias
flutter pub get              # descarga dependencias (como go mod download)
flutter pub add <paquete>    # agrega una dependencia a pubspec.yaml
flutter pub outdated         # muestra qué dependencias tienen versiones nuevas
flutter pub upgrade          # actualiza dentro de los rangos de pubspec.yaml

# Builds
flutter run                  # modo debug (hot reload, más lento)
flutter run --release        # rendimiento real; no hay hot reload
flutter build apk            # genera el APK para compartir → build/app/outputs/flutter-apk/
flutter build apk --split-per-abi   # un APK más liviano por arquitectura

# Limpieza (cuando algo raro pasa y no sabés por qué)
flutter clean                # borra build/ y .dart_tool/
flutter pub get              # ... y volver a bajar dependencias

# Actualizar Flutter
flutter upgrade

# Android / adb
adb devices                  # dispositivos visibles
adb logcat                   # logs del sistema Android (muy verboso)
adb kill-server              # reinicia el servidor de adb si se comporta raro
adb install -r app.apk       # instala un APK
```

Para depurar más a fondo: `flutter run` imprime en la terminal todo lo que hagas con
`debugPrint(...)`. **DevTools** (inspector de widgets, perfilador, red) se abre con la URL que
imprime `flutter run`, o con `dart devtools`.

## Problemas conocidos

| Síntoma | Causa | Solución |
|---|---|---|
| Android Studio se congela al abrir *Create Virtual Device* | Skiko no crea el contexto OpenGL (dos GPU, X11) | Crear el AVD por CLI (arriba), o agregar `-Dskiko.renderApi=SOFTWARE` en *Help → Edit Custom VM Options* |
| `adb server version doesn't match` / dispositivos que aparecen y desaparecen | Hay dos `adb` (el de apt y el del SDK) | `adb kill-server` y `sudo apt remove adb`; `which adb` debe apuntar a `~/Android/Sdk/platform-tools/adb` |
| `flutter devices` no muestra el emulador | Está apagado o todavía bootea | `emulator -avd pixel8 &` y esperar |
| `sdkmanager: command not found` | El PATH no está cargado | `source ~/.profile` |
| Falla Gradle / cosas raras tras cambiar dependencias | Caché inconsistente | `flutter clean && flutter pub get` |

## Glosario para venir de Go

| Go | Flutter / Dart |
|---|---|
| `go.mod` / `go.sum` | `pubspec.yaml` / `pubspec.lock` |
| `go get` / `go mod tidy` | `flutter pub add` / `flutter pub get` |
| `gofmt` | `dart format` |
| `staticcheck` / `go vet` | `flutter analyze` |
| `go test ./...` | `flutter test` |
| `go build` | `flutter build apk` |
| `package main` + `func main()` | `lib/main.dart` con `void main()` |
| Un paquete = un directorio | Un archivo = una librería; se importa con `package:workout_app/...` |
| Recompilar y reiniciar el servidor | Hot reload (`r`) |

## Estructura del proyecto

```
mobile/
├── pubspec.yaml          # manifiesto: nombre, versión, dependencias
├── pubspec.lock          # versiones exactas resueltas (se commitea en apps)
├── analysis_options.yaml # reglas del linter (flutter_lints)
├── lib/                  # TODO el código Dart de la app. Empieza en main.dart
├── test/                 # tests
└── android/              # proyecto Android nativo que envuelve a Flutter (se toca poco)
```

`build/` y `.dart_tool/` son generados y están en `.gitignore`.
