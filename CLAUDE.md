# Workout App (nombre a definir)

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

## Estado del proyecto

- Fase actual: definición de stack y modelado de datos (aún no hay código).
- Próximo paso: diseñar el modelo de datos en Postgres a partir de la documentación de
  ejercicios/planes en Excel que tengo que normalizar.

## Stack decidido

### Frontend (mobile)
- **Flutter + Dart** (Android primero; iOS queda pendiente por el costo de Apple Developer,
  USD 99/año, no es prioridad ahora).
- Motivo: mejor performance de UI que RN, un solo lenguaje coherente. Sin experiencia previa
  en Dart, pero se decide invertir el aprendizaje.

### Backend
- **Go** (net/http o un router liviano tipo Chi/Gin — a definir al implementar).
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
Cloud Run free tier). Ver el archivo de decisiones para el detalle de límites de cada
tier gratuito.

## Modelo de dominio (a completar)

Entidades previstas (sujeto a ajuste cuando se normalicen los Excel):
- `exercise`: ejercicio individual, con video, grupo muscular, tipo, instrucciones.
- `routine`: una rutina/plan de entrenamiento.
- `routine_block`: bloque dentro de una rutina, con un tipo (`superset`, `tabata`,
  `pyramid`, `straight_set`, etc.) y su configuración específica (rondas, tiempos de
  trabajo/descanso, etc.).
- `block_exercise`: relación entre un bloque y sus ejercicios (orden, series, reps, peso).
- `user`: usuario de la app.
- `session` / `session_log`: registro de una sesión de entrenamiento completada por un usuario.

_Pendiente: definir el modelo completo una vez normalizados los Excel de ejercicios y planes._

## Convenciones (a completar a medida que se implemente)

- Estructura de repo: **monorepo** con `/backend` (Go) y `/mobile` (Flutter) como carpetas
  separadas. Se prefirió sobre repos independientes porque el desarrollo es de una sola
  persona tocando ambos lados a la vez; separar en repos distintos es trivial más adelante
  si hiciera falta.
- Estilo de código, testing, CI/CD: pendiente.

## Decisiones descartadas (y por qué)

- **Kotlin/Swift nativos**: duplicaría el trabajo de mantener dos bases de código completas,
  sin necesidad real de funcionalidades nativas específicas.
- **MongoDB**: sin ventaja real en reactividad, performance ni concurrencia para este caso;
  peor ajuste al modelo de datos relacional del dominio.
- **Cloudflare Workers / Fly.io para el backend**: ver sección de hosting arriba.
