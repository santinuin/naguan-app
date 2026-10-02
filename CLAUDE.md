# Naguan App (FORJA DEL NAGUAN)

App móvil de calistenia estilo "Mammoth Hunters" (app que ya no existe), de uso personal
(yo + eventualmente algunos amigos). Prioridad: robustez y buenas prácticas sin sobre-ingeniería
de infraestructura — arquitectura que podría escalar si hiciera falta, pero sin pagar ese costo
por adelantado.

## Fin del proyecto

Además del fin productivo (tener la app funcionando), este proyecto tiene un **fin didáctico
explícito**: aprender Go, Supabase y Flutter/Dart (el usuario viene de Java/Spring WebFlux;
Dart y móvil son nuevos para él). Esto es relevante
a la hora de asistir en el desarrollo:

- Priorizar explicaciones y patrones idiomáticos de cada lenguaje/framework por sobre soluciones
  rápidas o "cajas negras", aunque existan atajos (librerías que abstraen todo, generadores de
  código, etc.).
- Está bien tomarse el tiempo de escribir código a mano en vez de generar todo automáticamente,
  cuando el objetivo es entender el porqué.
- Preferir explicar el razonamiento detrás de decisiones de Go y Flutter (por qué esta estructura,
  por qué este patrón de concurrencia, por qué este widget) en vez de solo entregar el resultado.

## Identidad y diseño

- **Nombre completo:** FORJA DEL NAGUAN. **Nombre corto:** NAGUAN (bajo el ícono, notificaciones,
  espacios de menos de 12 caracteres). Repo y paquetes: `naguan-app` / `naguan_app`.
- **Tagline:** «El título se gana. Serie a serie.» Naguan: palabra comechingona para *cacique*
  (un título que se gana por prestigio); la forja es donde se vuelve fuerte.
- **Sistema de diseño** (fuente de verdad: colores, tipografías, espaciados, voz, ícono):
  https://claude.ai/artifact/7JVK77PHuu8nn3TNCnJjGP — leer `project/README.md` y
  `project/tokens.json` antes de hacer UI. Resumen: neo-brutalista de serigrafía; tema oscuro
  **Hierro** (principal) y claro **Hueso**; un solo acento rosa óxido `#E0708C`; Archivo Black /
  Archivo / Space Mono; bordes gruesos de 3px, sombra dura sin blur, sin degradados ni emojis.
- **Voz:** imperativa, corta, voseo, títulos en MAYÚSCULAS. Vocabulario propio (Fragua = sesión,
  Senda = plan, Golpe = serie, Enfriá = descanso, Templado = sesión completada, Brasa = racha,
  Mojón = récord, Kamiare = comunidad). Usar solo palabras documentadas; nada de iconografía
  estereotipada (ver "Origen y respeto" en el README del sistema de diseño).
- **Ícono:** perfil de las sierras de Córdoba que forma una N. Oficial: variante C (sierra en
  tinta sobre rosa); alternativa aprobada: A. Android usa capas adaptativas (primer plano al 66%).

## Estado del proyecto

- Fase actual: **en producción** (Cloud Run + Supabase nube), usada desde un APK de release. Entorno de
  desarrollo listo y verificado: Go 1.27.1, Flutter 3.47.5 / Dart 3.13.4, Android SDK y
  emulador `pixel8`, Docker Desktop y Supabase local (ver "Particularidades del entorno").
- Hecho: navegación de punta a punta con el tema de Forja (Postgres → sqlc → API Go →
  Flutter): Sendas (`GET /programs`) → Senda con sus Fraguas (`GET /programs/{slug}`) →
  Fragua con bloques, vueltas (las idénticas consecutivas se compactan) y métricas
  (`GET /sessions/{id}`); renombre completo a `naguan-app`;
  tema de Forja en Flutter: fuentes empaquetadas y `ThemeData` Hierro/Hueso (ver
  "Convenciones"); ícono adaptativo de Android (variante C, con capa monocromática).
- Pendiente del tema: widget propio `ForjaButton` con la sombra dura que se hunde al
  presionar (`FilledButton` no la soporta); textura de grano sobre `bg`.
- Hecho (datos): esquema del catálogo y el importador `backend/cmd/seed` del nivel A
  (470 ejercicios, 209 progresiones, 5 programas, 191 sesiones), cargado en Supabase
  local (Postgres 17). API de lectura: `GET /programs`, `GET /programs/{slug}`,
  `GET /sessions/{id}` (sesión con bloques e ítems), `GET /exercises/{slug}` (detalle con
  videos, músculos, articulaciones y progresiones), con tests. Pendiente (más adelante, lo hace el usuario): auditar ejercicio por
  ejercicio en `backend/seed/exercise_names.csv`, incluidas las variantes numeradas
  ("Flexión anillas 1/2/3"), que según el caso son niveles o ejercicios distintos;
  renombrar cada sesión de cada programa con un nombre acorde (hoy muchas quedaron como
  "Sesión N"); sumar el calentamiento y el estiramiento que les faltan a los programas.
- Hecho (API y app del usuario):
  - Cimientos del servidor: config, middleware, rutas `/v1`.
  - Autenticación con Supabase Auth (ver `docs/autenticacion.md`).
  - Modelo del usuario: progreso por Senda con checks y reset, Fraguas templadas, Brasa,
    Mojones (API `/v1/me/...`), todo consumido desde la app.
  - Ejecución de una Fragua: timers, reps ajustables, pausa, registro y TEMPLADO con
    Mojones; pantalla encendida, retomar una Fragua interrumpida, cola offline con
    idempotencia (`client_id`) y vueltas de los AMRAP.
  - Ajustar una Fragua antes de empezar (solo para esa vez): reps/segundos y cambiar un
    ejercicio por una progresión (`session_edits.dart`, editor en hoja inferior); el
    ejercicio hecho se registra en `workout_item.exercise_id` y de ahí salen los Mojones.
- Próximos pasos (hoja de ruta), primero lo estructural y después el contenido:
  1. ~~Ingreso con biometría~~: hecho (sesión en `flutter_secure_storage` + candado
     `LockGate` con `local_auth`; ver `docs/autenticacion.md`).
  2. ~~Pantalla de ejercicio~~: hecha (`ExerciseScreen`, desde cada ejercicio de una
     Fragua y durante la ejecución: CÓMO SE HACE, la fila SIGUE y la vuelta del AMRAP;
     abrirla pausa la Fragua y al volver queda pausada).
  3. ~~Despliegue~~: hecho (ver "Producción" en Convenciones), con firma de release por
     clave propia (`mobile/android/key.properties`, no versionado; ver
     `docs/despliegue.md`, "Clave de firma").
  4. ~~Historial de Fraguas y Mojones~~: hecho (`HistoryScreen` paginada por cursor,
     `GET /v1/me/workouts?before=<id>`; `RecordsScreen` con el día de cada Mojón; acceso
     desde el inicio). Pendiente: el detalle de una Fragua templada (qué se hizo en cada
     ejercicio), que pide un `GET /v1/me/workouts/{id}`.
  5. Datos: niveles B y C (ver "Datos fuente"); ajustes de contenido (nombres de
     sesiones, calentamiento y estiramiento).

## Forma de trabajo

- **Dart/Flutter**: es el primer contacto del usuario con Dart y con desarrollo móvil, y el
  fin didáctico manda sobre la velocidad. **Claude escribe el código**, avanzando paso a paso
  y explicando cada concepto de Dart/Flutter que aparece (qué hace, por qué así, qué
  alternativa se descartó); el usuario después lo lee en detalle. Indicar un orden de
  lectura de los archivos.
- **Go y Supabase**: el usuario viene de **Java / Spring WebFlux** y usa el proyecto para
  aprender Go y Supabase (además de Flutter). Claude escribe el código Go, pero de forma
  pedagógica: explica los conceptos y el idioma de Go, con analogías a Java/Spring cuando
  ayudan (goroutines vs Mono/Flux, sqlc/pgx vs Spring Data/R2DBC, constructores explícitos
  vs inyección de Spring) y marcando dónde la intuición de Spring lleva a código no
  idiomático en Go.
- El usuario hace sus propios `git commit` y `git push`; Claude no commitea.
- Cada paso nuevo de tooling o de Flutter se acompaña de instrucciones para probarlo.
- **Documentos explicativos en `docs/`** (versionados): todo lo que valga la pena dejar
  por escrito sobre diseño, arquitectura o cómo funcionan los frameworks por debajo (Go,
  Flutter, Supabase). Se crean o amplían a medida que aparecen los temas. Hoy:
  `docs/go-para-devs-spring.md`, `docs/flutter-como-funciona.md`, `docs/autenticacion.md`,
  `docs/modelo-de-datos.md`, `docs/despliegue.md`.
- Guía de entorno, emulador y comandos útiles: `mobile/README.md`.

## Stack decidido

### Frontend (mobile)
- **Flutter + Dart** (Android primero; iOS queda pendiente por el costo de Apple Developer,
  USD 99/año, no es prioridad ahora).
- Motivo: mejor performance de UI que RN, un solo lenguaje coherente. Sin experiencia previa
  en Dart, pero se decide invertir el aprendizaje.

### Backend
- **Go** con `net/http` estándar (el mux de Go 1.22+ alcanza; sin Chi ni Gin por ahora).
- Motivo: ya tengo experiencia con Go, deploy simple (binario único), buen tipado,
  bajo consumo de recursos. No se elige por "concurrencia" (a esta escala no es un factor
  diferencial entre stacks), sino por conocimiento previo y simplicidad operativa.

### Base de datos
- **PostgreSQL**, administrado por **Supabase** (incluye Auth y Realtime).
- Motivo: el dominio es fuertemente relacional (ejercicios, rutinas, bloques tipo
  superset/tabata/pirámide, sets, usuarios, historial de sesiones) — encaja mejor con SQL
  que con un modelo de documentos (Mongo se descartó: sin ventajas reales en reactividad,
  performance o concurrencia para este caso, y peor ajuste al modelo de datos).
- Acceso a datos: **pgx v5** (driver + `pgxpool`) y **sqlc** (consultas en SQL → código Go
  tipado, validado contra las migraciones). Se descartó GORM (magia, esconde el SQL);
  squirrel queda como opción puntual si aparece una consulta muy dinámica.

### Autenticación
- Supabase Auth. Login simple (email/password o magic link) para mí y algunos amigos.

### Almacenamiento de videos
- **Hoy:** los videos son links de YouTube (shorts verticales y `youtu.be`) que vienen del
  índice de MH, y la app los muestra embebidos con `youtube_player_iframe` (WebView; sin
  sonido, en bucle). Solo `lib/catalog/youtube_video.dart` conoce YouTube.
- **Si hiciera falta independizarse de YouTube:** **Cloudflare R2** (S3-compatible, sin
  costo de egress) + `video_player`. No en Supabase Storage (el tier gratis es de 1GB).

### Hosting del backend
- **Google Cloud Run**. Se sube el binario Go como contenedor Docker, escala a cero cuando
  no hay uso (costo $0 en inactividad), 2M requests/mes gratis — muy por encima de lo que
  se va a necesitar.
- Se descartó Cloudflare Workers para el backend (pensado para JS/Wasm, no para un servidor
  Go persistente). Se descartó Fly.io (ya no tiene tier gratis real, ~USD 2-5/mes).

### Distribución de la app
- Android: APK compartido directo (sin pasar por Google Play), gratis.
- iOS: pendiente — requiere cuenta Apple Developer (USD 99/año) para TestFlight. No se
  contempla hasta que haga falta.

## Costo estimado actual

Con Android solamente: **~USD 0/mes** (Supabase free tier + Cloudflare R2 free tier +
Cloud Run free tier).

## Datos fuente

Los programas viven en `docs/source/` (**no versionado**, ver `.gitignore`): material comprado
o privado (Mammoth Hunters lo liberó al cerrar; los de Fitness Revolucionario son libros
comprados). Uso personal: si la app se abriera al público, habría que reemplazar planes y
videos. Al importar tenemos libertad total de **rediseñar IDs y nombres** para que encajen con
la estética y la filosofía de la app (sistema de diseño), y de simplificar.

- **Nivel A (primera etapa, automatizable):** `Indice de ejercicios.xlsx` (609 ejercicios,
  export de la base de MH) y los programas MH con hojas `Sesion N`: Aurum (12), Elite (69),
  Primal (20), Ring Master (40), Unbreakable (50). Filas desplegadas por vuelta:
  block, block_type, set, ex_id, ex_order, tiempo, reps.
- **Nivel B (segunda etapa):** Guerrera Espartana y Barra Libre (Excel con el plan en texto,
  p. ej. `4x15-20`, superseries `A1`/`A2`; Barra Libre usa cargas sobre el 1RM).
- **Nivel C (segunda etapa, transcripción):** solo en PDF: Muscle Hunters (12 semanas, 3
  niveles según un test), Desencadenado, Efecto Kettlebell, Sinergia, y los calentamientos y
  la movilidad de Unbreakable.
- Fuera de alcance: El Plan Revolucionario (nutrición y hábitos) y las hojas de medidas.

Reglas de saneamiento ya decididas:
- `ex_id` es la referencia confiable; **el video siempre sale del índice**. Los videos de
  los programas están mal en 431 filas (55 ejercicios, sobre todo Ring Master).
- Duplicados del índice (mismo ejercicio grabado por dos coaches, `LookupList.Coach_id`):
  se fusionan; canónico = coach **727** (el de Unbreakable y Ring Master), el otro ID queda
  como alias. Excepción: 5919/5927 no son duplicados (unilateral vs. bilateral).
- Encabezados con 8 variantes; `block_type` solo en la primera fila del bloque; números
  como texto; descanso = ejercicio "Descanso" (5968) → en el modelo es un ítem de descanso.

## Modelo de dominio

Detalle y decisiones en `docs/modelo-de-datos.md`. Migraciones en `supabase/migrations/`:
catálogo, cierre de la API REST de Supabase (RLS + revocar permisos a `anon` y
`authenticated`: **toda tabla nueva lleva `enable row level security`**) y registro de
entrenamiento (`workout`, `workout_item`, `program_reset`) e idempotencia + AMRAP
(`workout.client_id` único por usuario, `workout_amrap`) y el ejercicio realmente
hecho (`workout_item.exercise_id`). Alcance de la app:
calistenia, pero también fuerza con barra (Barra Libre) y movilidad ("flexifuerza").

- **Catálogo:** `exercise` (sin lado; `unilateral` indica que se hace de a un lado),
  `exercise_video` (uno, o uno por lado), `exercise_progression` (grafo más fácil → más
  difícil), `muscle`/`joint` con sus tablas de unión.
- **Sesiones:** `session` es una entidad propia (`kind`: workout, warmup, mobility,
  cooldown) para poder usarla suelta (p. ej. solo un calentamiento) o en varios programas;
  `program_session` da el orden dentro de un `program`.
- **Ejecución:** `block` (`type`: rounds, rounds_with_rest, tabata, superset, ladder,
  amrap; `time_cap_s` solo en amrap, cuyos ítems son una vuelta que se repite) y
  `block_item` **desplegado** (una fila por ejercicio y por vuelta, en orden): `kind`
  exercise | rest, lado, y tiempo **o** reps (nunca ambos; lo garantiza un `check`).
- Identificadores en inglés; el vocabulario de la app (Senda, Fragua, Golpe, Enfriá) es de
  la UI. IDs propios (`identity`) + `slug` donde hace falta una clave estable; los IDs de
  MH no entran en la base.
- **Entrenamiento (flexible):** cualquier Fragua de cualquier Senda, en cualquier orden y
  las veces que se quiera. Fuente de verdad: `workout` (Fragua templada, con `local_date`
  = día en el teléfono) y `workout_item` (reps o segundos reales). Todo se deriva:
  checks por Senda (templada después del último reset), próxima sugerida (primera sin
  check), Brasa y Mojones. `program_reset` guarda el último reset de cada Senda (resetear
  no borra historial). `user_id` referencia `auth.users`.
- **Brasa:** días entrenados; se apaga con 2 días hábiles seguidos sin entrenar; sábado y
  domingo opcionales (no cuentan como falta); `at_risk` si ya faltó un día hábil y hoy
  no entrenó. Función pura en `training/brasa.go`.
- **Mojones:** por ejercicio (ambos lados juntos), mejor reps y/o mejor duración; la
  primera vez e igualar no cuentan. `POST /v1/me/workouts` devuelve `new_records`.
- Segunda etapa (cuando haya datos que lo pidan): cargas (`load_kg` / % 1RM), rangos de
  reps (`4x15-20`), niveles por test.
- Nombres de los programas: se mantienen los originales por ahora.

## Convenciones (a completar a medida que se implemente)

- Estructura de repo: **monorepo** con `/backend` (Go) y `/mobile` (Flutter) como carpetas
  separadas. Se prefirió sobre repos independientes porque el desarrollo es de una sola
  persona tocando ambos lados a la vez; separar en repos distintos es trivial más adelante
  si hiciera falta.
- Identificadores: paquete Dart `naguan_app` y `applicationId` Android
  `com.santinuin.naguan_app` (difícil de cambiar una vez que hay instalaciones). Nombre en
  pantalla (label de Android): `Naguan`.
- Backend Go: `net/http` estándar (mux de Go 1.22+ con `"GET /ruta"`), sin framework.
  Módulo `github.com/santinuin/naguan-app/backend`. Layout:
  - `cmd/api`: arranque; arma las dependencias a mano (config → pool → `db.Queries` →
    `catalog.Service` → router).
  - `internal/config`: configuración desde el entorno, validada al arrancar: `PORT`
    (8080), `DATABASE_URL` (el Postgres de `supabase start`), `SUPABASE_URL`
    (`http://127.0.0.1:54321`), `SUPABASE_ISSUER` (por defecto `SUPABASE_URL` +
    `/auth/v1`; se pisa cuando la API llega a Supabase por otra dirección que la que
    figura en los tokens, p. ej. desde un contenedor), `REQUEST_TIMEOUT` (10s),
    `SHUTDOWN_TIMEOUT` (10s).
  - `internal/httpapi`: router, handlers y middleware (`logRequests` → `recoverPanics` →
    `withTimeout`, en ese orden). Rutas de la app bajo **`/v1`**, todas detrás de
    `requireUser` (token de Supabase obligatorio; `GET /v1/me` devuelve el usuario);
    `/health` público y sin versión.
  - `internal/training`: progreso por Senda, Fraguas templadas, Brasa (`brasa.go`, pura)
    y Mojones; transacciones con `inTx` (pgx + `q.WithTx`); errores de dominio
    `ValidationError` (400), `ErrProgramNotFound` (404) y `ErrUnknownUser` (401: token
    válido de una cuenta borrada, detectado por la FK a `auth.users`). Tests de integración contra la base local con `TEST_DATABASE_URL` (se saltean
    sin ella).
  - `internal/auth`: valida los JWT de Supabase (ES256, claves públicas del JWKS de
    `SUPABASE_URL`, con `golang-jwt` + `keyfunc`) y lleva el usuario en el `context`
    (`auth.WithUser` / `auth.UserFrom`). La autorización por usuario se hace en Go (la API
    se conecta como `postgres` y no usa RLS).
    Define las interfaces que consume (`Catalog`) y traduce errores a status
    (`ErrNotFound` → 404, `DeadlineExceeded` → 504, `Canceled` → sin respuesta; el resto,
    500 sin detalle).
  - `internal/catalog`: tipos de respuesta JSON (separados de las filas de la base) y
    armado (p. ej. agrupar los ítems planos en bloques).
  - `internal/db`: **generado por sqlc** (`sqlc generate` desde `backend/`, config en
    `sqlc.yaml`); las consultas viven en `internal/db/queries/*.sql`. No editar el `.go`.
  - `cmd/seed` + `internal/mhimport`: importador de los programas (ver `backend/README.md`).
  - Interfaces chicas y del lado del consumidor; nada de interfaz + `Impl` por servicio.
- Notas de Go para quien viene de Spring: `docs/go-para-devs-spring.md` (se completa a
  medida que aparecen conceptos).
- Testing: backend con `httptest` y tests de integración
  (`TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres go test ./...`);
  mobile con `flutter test`. Linter mobile: `flutter analyze`.
  En mobile, las dependencias se inyectan por constructor (`main` crea el `CatalogClient` y lo
  pasa hacia abajo) para poder testear: los clientes HTTP reciben un `http.Client` opcional
  (en tests, `MockClient` de `package:http/testing.dart`), y las pantallas reciben el cliente
  (en tests, un fake con `implements` y un `Completer` para controlar cuándo responde).
- Tema mobile en `mobile/lib/theme/`: `forja_tokens.dart` tiene los valores crudos del
  sistema de diseño (`ForjaPalette.hierro`/`.hueso`, `ForjaSpace`, `ForjaRadius`,
  `ForjaBorder`, `ForjaFonts`); `forja_theme.dart` los mapea a `ThemeData` (`forjaHierro`,
  `forjaHueso`). Mapeo de estilos: hero→`displayLarge`, display→`displayMedium`,
  title→`titleLarge`, heading→`headlineSmall`, body→`bodyLarge`/`bodyMedium`,
  label→`labelSmall`. Lo que Material no cubre (paleta completa, `stat`, `bodyStrong`) va en
  la `ThemeExtension` `Forja`, accesible con `context.forja`. En las pantallas: estilos
  desde el tema, nunca `TextStyle`/colores escritos a mano. Error = `signal` (el sistema de
  diseño no define un color de error). La app usa `ThemeMode.dark` (Hierro) fijo.
- Ícono: fuentes en `mobile/branding/icon/` (`icon_c.svg/.png` del sistema de diseño;
  `foreground` y `monochrome` derivados, sin fondo ni grano, con el rayado como huecos).
  Los recursos de Android se generan con `flutter_launcher_icons` (config en
  `pubspec.yaml`, inset 17% → dibujo al 66%): `dart run flutter_launcher_icons`. No editar a
  mano los `mipmap-*`/`drawable-*` generados.
- Datos: migraciones en `supabase/migrations/` (convención de la CLI de Supabase); el seed
  `supabase/seed.sql` se genera con `backend/cmd/seed` y **no se versiona** (contenido de
  la fuente; el repo es público por ahora). Sí se versiona `backend/seed/exercise_names.csv`
  (solo nombres). Ver `backend/README.md`.
- Autenticación en mobile: `supabase_flutter` solo para Auth (los datos van por la API Go).
  `lib/auth/`: `AuthService` (interfaz propia; `SupabaseAuthService` la implementa),
  `LoginScreen` y `AuthGate` (elige ingreso o app escuchando el stream de sesión). La
  sesión se guarda cifrada (`SecureSessionStorage` sobre `SecureLocalStore`, con
  `flutter_secure_storage`). `LockGate` (en `MaterialApp.builder`, por encima del
  Navigator) pide huella/PIN vía `DeviceLock` (`local_auth`) al abrir con sesión guardada y
  al volver tras 5 min en segundo plano; Android: `FlutterFragmentActivity`, temas
  AppCompat, `allowBackup="false"`. El
  `ApiClient` recibe una función `accessToken` y manda `Authorization: Bearer`; ante un
  401 cierra la sesión.
  Configuración en `lib/config.dart` (`String.fromEnvironment` con valores locales por
  defecto; se pisan con `--dart-define`).
- Mobile organizado por funcionalidad: `lib/catalog/` (modelos, cliente, pantallas;
  `ExerciseScreen` recibe un `videoBuilder` para que los tests no necesiten WebView),
  `lib/training/` (progreso, Brasa, Mojones; `history/` con el historial paginado
  (`WorkoutHistory`, un `ChangeNotifier`), los Mojones y las fechas en castellano;
  `execution/` con `WorkoutRunner`, el motor
  de una Fragua: `ChangeNotifier` con lógica pura y reloj inyectable, testeado sin
  widgets; `offline/` con la Fragua en curso y la cola sin señal; `TrainingServices`
  agrupa cliente + almacenes), `lib/common/` (`LocalStore`: interfaz sobre
  `shared_preferences`, en memoria en los tests; `ApiClient`: HTTP compartido por los clientes, token,
  errores, `onUnauthorized` → cerrar sesión; `LoadView<T>`: cargando/error/datos;
  `MarkdownText`: Markdown mínimo propio para las descripciones, sin paquete) y
  `lib/theme/` (tokens, `ThemeData`, widgets propios como `ForjaPill`). Navegación con
  `Navigator.push` + `MaterialPageRoute`, datos por constructor (go_router cuando haya
  deep links). Modelos con
  `fromJson` a mano (pattern matching de Dart 3), sin generación de código por ahora. Los
  clientes decodifican el cuerpo con `utf8.decode(bodyBytes)` (la API no manda charset).
  La URL base de la API es `apiBaseUrl` en `lib/config.dart` (`http://10.0.2.2:8080/v1` en
  el emulador); los clientes agregan la ruta.
- Fuentes: TTF estáticos en `mobile/assets/fonts/` (con sus licencias OFL), declarados en
  `pubspec.yaml`; no se usa `google_fonts` (descarga al primer uso, falla sin señal).
  Las licencias OFL van como assets y se registran con `LicenseRegistry`
  (`lib/theme/font_licenses.dart`); se ven en LICENCIAS, al pie de SENDAS
  (`showLicensePage`), provisoriamente: mudar el botón a la pantalla de inicio (o a
  "Acerca de"/perfil) cuando exista. Una fuente nueva suma su `.txt` ahí y en
  `pubspec.yaml`.
- Al elegir paquetes de Dart, verificar en pub.dev que soporten iOS además de Android, para
  no cerrar esa puerta (agregar iOS después es `flutter create --platforms=ios .`, pero
  compilarlo requiere una Mac o CI en la nube, p. ej. Codemagic).
- En el emulador Android, la PC host se alcanza en `10.0.2.2` (no `localhost`); HTTP sin
  cifrar está bloqueado por defecto en Android y hay que habilitarlo solo en desarrollo.
- Despliegue (guía completa en `docs/despliegue.md`): API en Cloud Run
  (`southamerica-east1`, `--source .` con `backend/Dockerfile` multi-etapa sobre
  distroless, escala a cero, `--max-instances 2`), base y Auth en Supabase nube
  (`sa-east-1`; la API conecta por el **Session pooler**, puerto 5432, IPv4;
  `DATABASE_URL` en Secret Manager). La app de release se configura con
  `--dart-define` (`API_BASE_URL`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`). Alerta de
  presupuesto de USD 1 en Google Cloud. Registro público deshabilitado en Supabase.
- **Producción** (desplegada el 2026-10-01): proyecto de Supabase `naguan`, ref
  `uglblscyrtrurpdlxssj` (`https://uglblscyrtrurpdlxssj.supabase.co`, sa-east-1); proyecto de
  Google Cloud `naguan` (cuenta de facturación "Naguan" con alerta de USD 1); servicio de
  Cloud Run `naguan-api` en `https://naguan-api-164976317185.southamerica-east1.run.app`;
  secreto `database-url` en Secret Manager (solo lo lee la cuenta de servicio de Cloud
  Run). Redesplegar: `gcloud run deploy naguan-api --source . --region
  southamerica-east1` desde `backend/` (conserva variables y secretos). Migraciones
  nuevas: `supabase db push` (el repo está vinculado con `supabase link`). `supabase login`
  y `gcloud auth login` se corren en la terminal del usuario (necesitan TTY).
- CI: `.github/workflows/ci.yml` (gofmt, vet, tests, `sqlc diff` con sqlc 1.31.1, build
  de Docker; dart format, analyze y tests de Flutter). CD: a mano por ahora.

## Particularidades del entorno de desarrollo

- Android Studio se congela al abrir *Create Virtual Device* en esta máquina (Skiko no crea
  el contexto OpenGL: dos GPU, X11). El emulador se crea y arranca por CLI; ver
  `mobile/README.md`.
- Asegurarse de que haya un único `adb` (el del SDK en `~/Android/Sdk/platform-tools`) para
  evitar conflictos de versión del servidor.
- Flutter está en `~/development/flutter/bin`, cargado en el `PATH` del perfil interactivo;
  en shells no interactivos (los de Claude) hay que agregarlo a mano.
- El warning `sdkmanager is deprecated` durante `flutter run` es inofensivo.
- Memoria de Gradle acotada a 4G en `mobile/android/gradle.properties`: con los 8G de la
  plantilla, el build de release moría por falta de memoria (exit 137) con el emulador y
  Docker abiertos.
- Docker: el engine nativo (`/var/run/docker.sock`) requiere el grupo `docker`, que el
  usuario no tiene; se usa Docker Desktop (contexto `desktop-linux`), que hay que abrir a
  mano. No hay `psql` en el host: usar `docker exec supabase_db_naguan-app psql -U postgres`.
- Supabase local: CLI 2.119 en `~/.local/bin/supabase`; sqlc en `~/.local/bin/sqlc`
  (binarios de los releases de GitHub).
  Se levanta solo lo necesario por ahora (Postgres 17, Auth y Studio):
  `supabase start -x realtime,storage-api,imgproxy,mailpit,edge-runtime,logflare,vector,supavisor`.
  Usuario de prueba local: `prueba@naguan.local` / `forja-local-123`. Los tokens se firman
  con ES256; el JWKS está en `http://127.0.0.1:54321/auth/v1/.well-known/jwks.json`.
  Postgres en `127.0.0.1:54322` (postgres/postgres), Studio en `http://127.0.0.1:54323`.
  `supabase db reset` reaplica migraciones + `supabase/seed.sql`; `supabase stop` lo apaga.

## Decisiones descartadas (y por qué)

- **Kotlin/Swift nativos**: duplicaría el trabajo de mantener dos bases de código completas,
  sin necesidad real de funcionalidades nativas específicas.
- **MongoDB**: sin ventaja real en reactividad, performance ni concurrencia para este caso;
  peor ajuste al modelo de datos relacional del dominio.
- **Cloudflare Workers / Fly.io para el backend**: ver sección de hosting arriba.
