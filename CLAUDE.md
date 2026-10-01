# Naguan App (FORJA DEL NAGUAN)

App móvil de calistenia estilo "Mammoth Hunters" (app que ya no existe), de uso personal
(yo + eventualmente algunos amigos). Prioridad: robustez y buenas prácticas sin sobre-ingeniería
de infraestructura — arquitectura que podría escalar si hiciera falta, pero sin pagar ese costo
por adelantado.

## Fin del proyecto

Además del fin productivo (tener la app funcionando), este proyecto tiene un **fin didáctico
explícito**: afianzar conocimientos de Go y aprender Flutter/Dart desde cero. Esto es relevante
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

- Fase actual: conectar el backend Go a la base (local) y exponer el catálogo. Entorno de
  desarrollo listo y verificado: Go 1.27.1, Flutter 3.47.5 / Dart 3.13.4, Android SDK y
  emulador `pixel8`, Docker Desktop y Supabase local (ver "Particularidades del entorno").
- Hecho: backend Go mínimo con `GET /health` (con tests); app Flutter con `HealthClient` y
  `HomeScreen` que consulta `/health` desde el emulador; renombre completo a `naguan-app`;
  tema de Forja en Flutter: fuentes empaquetadas y `ThemeData` Hierro/Hueso (ver
  "Convenciones"); ícono adaptativo de Android (variante C, con capa monocromática).
- Pendiente del tema: widget propio `ForjaButton` con la sombra dura que se hunde al
  presionar (`FilledButton` no la soporta); textura de grano sobre `bg`; registrar las
  licencias OFL de las fuentes con `LicenseRegistry` antes de compartir el APK.
- Hecho (datos): esquema del catálogo y el importador `backend/cmd/seed` del nivel A
  (470 ejercicios, 209 progresiones, 5 programas, 191 sesiones), cargado en Supabase
  local (Postgres 17). Pendiente (más adelante, lo hace el usuario): auditar ejercicio por
  ejercicio en `backend/seed/exercise_names.csv`, incluidas las variantes numeradas
  ("Flexión anillas 1/2/3"), que según el caso son niveles o ejercicios distintos.
- Próximos pasos (hoja de ruta):
  1. Acceso a datos desde Go: elegir sqlc vs squirrel, conectar a la base local y
     exponer los primeros endpoints del catálogo.
  2. Supabase en la nube: crear el proyecto y aplicar migración y seed.
  3. Datos: niveles B y C (ver "Datos fuente").
  4. Auth con Supabase y validación del JWT en Go.
  5. Funcionalidades: catálogo de ejercicios, rutinas, ejecución de sesión (timers),
     historial.

## Forma de trabajo

- **Dart/Flutter**: es el primer contacto del usuario con Dart y con desarrollo móvil, y el
  fin didáctico manda sobre la velocidad. Por defecto Claude guía con explicaciones,
  fragmentos cortos y el porqué de cada decisión, y revisa lo que el usuario escribe. Si el
  usuario lo pide, Claude escribe el código y lo acompaña de una explicación detallada de
  los conceptos de Dart/Flutter que aparecen, para que el usuario lo lea y aprenda.
- **Go**: el usuario ya lo conoce, así que Claude puede escribir el código y explicar solo
  las decisiones no obvias.
- El usuario hace sus propios `git commit` y `git push`; Claude no commitea.
- Cada paso nuevo de tooling o de Flutter se acompaña de instrucciones para probarlo.
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
- ORM: a definir (candidato: sqlc o un query builder tipo squirrel, dado que el backend es Go).

### Autenticación
- Supabase Auth. Login simple (email/password o magic link) para mí y algunos amigos.

### Almacenamiento de videos
- **Cloudflare R2** (S3-compatible, sin costo de egress) + CDN. Los videos de ejercicios
  NO van en Supabase Storage (ahí el tier gratis es de solo 1GB, se llenaría rápido con video).

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

Esquema en `supabase/migrations/20261001000000_catalog.sql`. Alcance de la app:
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
- Segunda etapa (cuando haya datos que lo pidan): cargas (`load_kg` / % 1RM), rangos de
  reps (`4x15-20`), niveles por test, y las tablas de registro de lo entrenado.
- Nombres de los programas: se mantienen los originales por ahora.

## Convenciones (a completar a medida que se implemente)

- Estructura de repo: **monorepo** con `/backend` (Go) y `/mobile` (Flutter) como carpetas
  separadas. Se prefirió sobre repos independientes porque el desarrollo es de una sola
  persona tocando ambos lados a la vez; separar en repos distintos es trivial más adelante
  si hiciera falta.
- Identificadores: paquete Dart `naguan_app` y `applicationId` Android
  `com.santinuin.naguan_app` (difícil de cambiar una vez que hay instalaciones). Nombre en
  pantalla (label de Android): `Naguan`.
- Backend Go: `net/http` estándar (mux de Go 1.22+ con `"GET /ruta"`) por ahora, sin
  framework. Layout: `cmd/api` (arranque) e `internal/httpapi` (router y handlers). El puerto
  viene de `PORT` (Cloud Run), 8080 por defecto. Módulo:
  `github.com/santinuin/naguan-app/backend`.
- Testing: backend con `httptest`; mobile con `flutter test`. Linter mobile: `flutter analyze`.
  En mobile, las dependencias se inyectan por constructor (`main` crea el `HealthClient` y lo
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
- Fuentes: TTF estáticos en `mobile/assets/fonts/` (con sus licencias OFL), declarados en
  `pubspec.yaml`; no se usa `google_fonts` (descarga al primer uso, falla sin señal).
- Al elegir paquetes de Dart, verificar en pub.dev que soporten iOS además de Android, para
  no cerrar esa puerta (agregar iOS después es `flutter create --platforms=ios .`, pero
  compilarlo requiere una Mac o CI en la nube, p. ej. Codemagic).
- En el emulador Android, la PC host se alcanza en `10.0.2.2` (no `localhost`); HTTP sin
  cifrar está bloqueado por defecto en Android y hay que habilitarlo solo en desarrollo.
- Estilo de código (más allá de gofmt / dart format), CI/CD: pendiente.

## Particularidades del entorno de desarrollo

- Android Studio se congela al abrir *Create Virtual Device* en esta máquina (Skiko no crea
  el contexto OpenGL: dos GPU, X11). El emulador se crea y arranca por CLI; ver
  `mobile/README.md`.
- Asegurarse de que haya un único `adb` (el del SDK en `~/Android/Sdk/platform-tools`) para
  evitar conflictos de versión del servidor.
- Flutter está en `~/development/flutter/bin`, cargado en el `PATH` del perfil interactivo;
  en shells no interactivos (los de Claude) hay que agregarlo a mano.
- El warning `sdkmanager is deprecated` durante `flutter run` es inofensivo.
- Docker: el engine nativo (`/var/run/docker.sock`) requiere el grupo `docker`, que el
  usuario no tiene; se usa Docker Desktop (contexto `desktop-linux`), que hay que abrir a
  mano. No hay `psql` en el host: usar `docker exec supabase_db_naguan-app psql -U postgres`.
- Supabase local: CLI 2.119 en `~/.local/bin/supabase` (binario del release de GitHub).
  Se levanta solo lo necesario por ahora (Postgres 17 + Studio):
  `supabase start -x gotrue,realtime,storage-api,imgproxy,mailpit,edge-runtime,logflare,vector,supavisor`.
  Postgres en `127.0.0.1:54322` (postgres/postgres), Studio en `http://127.0.0.1:54323`.
  `supabase db reset` reaplica migraciones + `supabase/seed.sql`; `supabase stop` lo apaga.

## Decisiones descartadas (y por qué)

- **Kotlin/Swift nativos**: duplicaría el trabajo de mantener dos bases de código completas,
  sin necesidad real de funcionalidades nativas específicas.
- **MongoDB**: sin ventaja real en reactividad, performance ni concurrencia para este caso;
  peor ajuste al modelo de datos relacional del dominio.
- **Cloudflare Workers / Fly.io para el backend**: ver sección de hosting arriba.
