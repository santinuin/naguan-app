# Go para quien viene de Java / Spring WebFlux

Notas de aprendizaje del proyecto: cómo se traducen las ideas de Spring (y en particular
de WebFlux) a Go, y dónde la intuición de Spring lleva a código no idiomático. Se completa
a medida que aparecen conceptos nuevos.

## Concurrencia: el cambio de modelo mental

Los dos resuelven el mismo problema (atender miles de requests concurrentes sin miles de
hilos del sistema operativo) de formas opuestas:

| | Spring WebFlux | Go |
|---|---|---|
| Modelo | Pocos hilos (event loop de Netty) que **nunca se pueden bloquear** | Una **goroutine por request**; son baratísimas (~8 KB de stack inicial, cientos de miles sin problema) |
| Cómo se escribe el I/O | `Mono`/`Flux` y operadores (`flatMap`, `zip`, `onErrorResume`...) | Código secuencial "bloqueante": `rows, err := db.Query(ctx, ...)` |
| Quién evita bloquear el hilo | El programador, con la API reactiva | **El runtime de Go**: si una goroutine espera I/O, la estaciona y usa el hilo para otra |
| Cancelación | La señal de cancelación de la suscripción | `context.Context`, pasado explícitamente como primer parámetro |
| Errores | Excepciones / `Mono.error` | Valores: `if err != nil { return err }` |
| Inyección de dependencias | Contenedor de Spring (`@Autowired`, `@Bean`) | No hay contenedor: todo se arma a mano en `main` |

**La idea clave:** Go da la escalabilidad de WebFlux escribiendo código como el de Spring
MVC clásico. El trabajo que en Reactor se hace con operadores, en Go lo hace el scheduler
del runtime. Por eso no existe nada parecido a `Mono<T>`: una función que consulta la base
devuelve `(T, error)`.

`net/http` ya crea una goroutine por request: cada handler corre en la suya y puede
"bloquearse" esperando a Postgres sin frenar a nadie.

### `context.Context`, lo más parecido a Reactor

Cada request trae un contexto (`r.Context()`). Si el cliente se desconecta, se cancela; y
si se lo pasaste a la consulta (`db.Query(ctx, ...)`), **la consulta se cancela en
Postgres**. Es la propagación de cancelación de una suscripción reactiva, pero explícita:
si te olvidás de pasar el `ctx`, se corta la cadena. Por eso la convención es que toda
función que haga I/O reciba `ctx context.Context` como primer parámetro.

El contexto también lleva deadlines (`context.WithTimeout`): el equivalente a un
`.timeout(Duration)` de Reactor, pero que se hereda hacia abajo a todo lo que reciba ese
contexto.

### Ejemplo en el repo: el graceful shutdown

`backend/cmd/api/main.go` hace a mano lo que en Spring Boot es `server.shutdown=graceful`:
`go func() {...}()` lanza el servidor en otra goroutine, un *channel* (`errCh`, un tubo
tipado entre goroutines) trae su error, y `select` espera lo que pase primero: ese error o
la señal de apagado. Después, `srv.Shutdown` deja terminar los requests en curso.

## Acceso a datos

| Java / Spring | Go (en este proyecto) |
|---|---|
| Driver JDBC / R2DBC | `pgx` v5, driver nativo de Postgres |
| HikariCP | `pgxpool` |
| Spring Data repository / `@Query` | Consultas en `.sql` + código generado por **sqlc** |
| jOOQ con generación de código | sqlc es lo más parecido: valida las consultas contra el esquema al generar |
| Criteria API / DSL de jOOQ | `squirrel` (query builder en tiempo de ejecución); no lo usamos por ahora |
| JPA / Hibernate | GORM; descartado (mucha magia, esconde el SQL) |
| `spring.datasource.url` | Variable de entorno `DATABASE_URL` |

## Estructura y estilo

| Spring | Go |
|---|---|
| `@RestController` | Handlers en `internal/httpapi` (funciones `func(w, r)`) |
| `@Service` | Paquete de dominio (`internal/catalog`) |
| Repository | Código generado por sqlc (`internal/db`) |
| `@Configuration` + contenedor | `main` arma las dependencias y las pasa por constructor |
| Interfaz + `Impl` por cada servicio | **No.** Las interfaces son chicas y las define quien las usa, cuando hace falta (p. ej. para un fake en un test) |
| Excepción → `@ControllerAdvice` | El handler revisa el error y decide el status (`errors.Is(err, catalog.ErrNotFound)` → 404) |

## Visibilidad y estructura de directorios

| Java | Go |
|---|---|
| `public` / `private` / `protected` / package-private | Solo dos niveles, por la **mayúscula inicial**: `NewService` está exportado; `groupBlocks` es privado del paquete |
| Módulo JPMS que no exporta un paquete (`module-info.java`) | Directorio **`internal/`**: lo hace cumplir el compilador |
| Varias clases con `main` en un proyecto, cada una su jar ejecutable | `cmd/<nombre>/main.go`: un ejecutable por subdirectorio (pura convención) |

### `internal/`

Un paquete dentro de `internal/` **solo lo pueden importar los paquetes que viven bajo el
directorio padre de ese `internal`**. En este repo el padre es `backend/`: `cmd/api`,
`cmd/seed` y los paquetes de `internal/` se importan entre sí sin problema, pero código de
fuera de `backend/` que intente `import ".../backend/internal/catalog"` no compila
(`use of internal package ... not allowed`).

Es la señal de "esto es implementación, no una librería": se puede cambiar la firma de
`catalog.Service` o reorganizar `db` sabiendo que nadie fuera del módulo depende de eso.
En una aplicación, casi todo va en `internal/`; el código pensado para que otros lo
importen va en la raíz del módulo o en `pkg/`.

### `cmd/`

No es especial para el compilador: es convención. Cada subdirectorio es un binario
(`package main` con su `func main()`): acá `cmd/api` (el servidor) y `cmd/seed` (el
importador), ambos usando paquetes de `internal/`.

## Middleware: el `WebFilter` de Go

Un middleware es una función que recibe un `http.Handler` y devuelve otro que lo envuelve
(el patrón *decorator*): hace algo antes, llama a `next.ServeHTTP(w, r)`, y hace algo
después. Es el mismo papel que un `WebFilter` de WebFlux, sin anotaciones ni orden por
`@Order`: el orden es el de la llamada a `chain` en `httpapi.NewRouter`.

```go
type Middleware func(next http.Handler) http.Handler

chain(mux, logRequests, recoverPanics, withTimeout(cfg.RequestTimeout))
// logRequests ( recoverPanics ( withTimeout ( mux ) ) )
```

El primero de la lista es el más externo: ve el request primero y la respuesta último. Por
eso `logRequests` va afuera: así registra también el 500 que produce `recoverPanics`.

| Middleware | Qué hace | En Spring |
|---|---|---|
| `logRequests` | Una línea de log por request (método, ruta, status, bytes, duración) | Un `WebFilter` de logging / el access log de Netty |
| `recoverPanics` | Convierte un *panic* en un 500 con el formato de la API | Un `@ExceptionHandler(Throwable.class)` |
| `withTimeout` | Pone un deadline al `context.Context` del request | `.timeout(Duration)` sobre el `Mono` de la respuesta |

### Envolver el `ResponseWriter`: *embedding*

Para saber qué status devolvió el handler, `logRequests` le pasa un `statusRecorder`:

```go
type statusRecorder struct {
    http.ResponseWriter // campo sin nombre: embedding
    status, bytes int
}
```

Un campo sin nombre **promociona** sus métodos: `statusRecorder` tiene `Header()`,
`Write()` y `WriteHeader()` sin escribirlos, y redefine solo los que necesita espiar. No
es herencia (no hay `super`, ni polimorfismo sobre el tipo embebido): es composición con
delegación automática. Cumple la interfaz `http.ResponseWriter`, así que el handler no se
entera de que le cambiaron el writer.

### `panic` y `recover` no son excepciones

En Go los errores esperables se devuelven como valores. Un `panic` es para errores de
programación (un map nil, un índice fuera de rango) y corta la ejecución subiendo por la
pila. Solo se atrapa con `recover()` dentro de una función diferida (`defer`).

`net/http` ya evita que un panic en un handler tumbe el servidor, pero corta la conexión
sin responder; `recoverPanics` hace que el cliente reciba un 500 legible y que el log
tenga el stack trace. Ojo: un panic en **otra** goroutine (una lanzada con `go`) no pasa
por ningún middleware y sí tumba el proceso.

### Timeouts con `context`

`withTimeout` no puede matar el handler (en Go no se detiene una goroutine desde afuera):
cancela su contexto, y todo lo que lo respeta (las consultas de `pgx`, un `http.Client`)
se interrumpe y devuelve `context.DeadlineExceeded`. `writeError` lo traduce a **504**.
Si el que cancela es el cliente (cerró la app), el error es `context.Canceled`: no se
responde ni se registra como error del servidor.

Todo esto funciona por la cadena de errores: `fmt.Errorf("...: %w", err)` envuelve, y
`errors.Is(err, context.DeadlineExceeded)` la recorre aunque el error esté varias capas
abajo. Es el equivalente a buscar una excepción en la cadena de `getCause()`.

## Configuración

`internal/config` es el `@ConfigurationProperties` del proyecto: un struct tipado que se
carga una vez en `main` desde variables de entorno (`PORT`, `DATABASE_URL`,
`REQUEST_TIMEOUT`, `SHUTDOWN_TIMEOUT`), con valores por defecto y validación. Si algo está
mal, el servidor no arranca y el error lista **todos** los problemas juntos.

Para testearlo sin tocar el entorno real, la función que busca variables se recibe como
parámetro (`load(lookup func(string) (string, bool))`): en Go las funciones son valores,
y pasar una función es la forma más liviana de inyectar una dependencia.

## Versionado de la API

Las rutas de la app van bajo `/v1` (`/health` no, porque la consulta la infraestructura).
Cuando haya que romper el contrato (renombrar un campo, cambiar una forma), `/v1` y `/v2`
conviven mientras las apps instaladas se actualizan: en móvil no se puede forzar que todos
actualicen a la vez.

## Transacciones: `@Transactional`, explícito

```go
func (s *Service) inTx(ctx context.Context, fn func(q *db.Queries) error) error {
    tx, err := s.pool.Begin(ctx)
    if err != nil { return err }
    defer tx.Rollback(ctx)          // si ya hubo Commit, no hace nada
    if err := fn(s.q.WithTx(tx)); err != nil {
        return err                  // el defer deshace todo
    }
    return tx.Commit(ctx)
}
```

- Lo que en Spring hace un proxy alrededor de un método anotado, en Go es una función
  que recibe otra función: se ve exactamente qué corre dentro de la transacción.
- **`defer tx.Rollback(ctx)` justo después de `Begin`** es el idioma: cualquier salida
  temprana (un error, un panic) deshace la transacción, y después de un `Commit` exitoso
  el `Rollback` no hace nada.
- **`q.WithTx(tx)`** (generado por sqlc) devuelve las mismas consultas pero sobre la
  transacción: el mismo código funciona dentro o fuera de una.
- Ejemplo real: `training.StartProgram` termina la Senda anterior y crea la nueva en una
  transacción; `RecordWorkout` valida, crea el workout y sus ítems, y si un ítem es
  inválido no queda nada a medias (hay un test de integración que lo verifica).

### Inserción masiva: `:copyfrom`

`CreateWorkoutItems` usa el protocolo **COPY** de Postgres (anotación `:copyfrom` en
sqlc): manda todas las filas en un solo flujo, mucho más rápido que un `INSERT` por fila.
Es el equivalente a un batch de JDBC.

## `errors.Is` vs `errors.As`

| | Busca en la cadena de errores... | Para | En Java |
|---|---|---|---|
| `errors.Is(err, ErrX)` | un **valor** puntual | errores sin datos (`ErrNotFound`, `context.DeadlineExceeded`) | comparar contra una instancia |
| `errors.As(err, &target)` | un **tipo**, y lo asigna a `target` | errores que llevan datos (`*ValidationError` con su mensaje) | `catch (ValidationException e)` |

```go
var verr *training.ValidationError
if errors.As(err, &verr) {
    writeJSON(w, 400, errorResponse{Error: verr.Msg})
}
```

Los dos recorren la cadena armada con `fmt.Errorf("...: %w", err)`.

**Cada error en su capa:** `training.ValidationError` es del dominio ("el ítem es un
descanso"); `httpapi.badRequestError` es de HTTP ("el JSON está roto"). `writeError`
traduce ambos a 400, pero el dominio no sabe nada de HTTP.

## Tests de integración

`internal/training/training_integration_test.go` corre contra un Postgres real (el de
`supabase start`), con el esquema y el seed cargados:

```bash
TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres go test ./...
```

- Sin `TEST_DATABASE_URL`, `t.Skip` los saltea: `go test ./...` funciona sin base.
- Cada test crea su propio usuario en `auth.users` y lo borra con `t.Cleanup` (el
  `on delete cascade` se lleva sus datos). Así los tests no se pisan entre sí.
- Prueban lo que un fake no puede: las consultas SQL, las transacciones, el índice único
  parcial y el aislamiento entre usuarios.

Es el `@SpringBootTest` con Testcontainers, pero contra la base local que ya está
levantada.

## Inyectar el reloj

`NewWorkout.validate(now time.Time)` recibe la hora actual en vez de llamar a
`time.Now()` adentro. Así el resultado depende solo de sus argumentos, y los tests usan
una hora fija. Es lo mismo que pasar un `java.time.Clock`. Lo aprendimos con un test que
fallaba según la hora del día en que se corría.

## Diseño de la API REST

| Método y ruta | Qué hace | Status |
|---|---|---|
| `GET /v1/me/programs` | Progreso en cada Senda (checks, próxima sugerida) | 200 |
| `GET /v1/me/programs/{slug}` | Progreso en una Senda, con los ids de las Fraguas con check | 200, o 404 |
| `DELETE /v1/me/programs/{slug}/progress` | Resetear la Senda (el historial no se borra) | 204 (sin cuerpo) |
| `POST /v1/me/workouts` | Registrar una Fragua templada; devuelve los Mojones superados | 201 Created |
| `GET /v1/me/workouts?limit=` | Historial | 200 |
| `GET /v1/me/stats?today=AAAA-MM-DD` | Brasa y total de Fraguas | 200 |
| `GET /v1/me/records` | Mojones | 200 |

- **Todo lo del usuario va bajo `/v1/me`**: el usuario sale del token, no de la URL.
- **`DELETE .../progress`** para resetear: lo que se borra es el recurso "progreso" (los
  checks), no la Senda ni el historial. Un `POST .../reset` también sería válido; el
  `DELETE` expresa mejor que el estado queda vacío.
- **`readJSON`** es el `@RequestBody`, pero estricto: limita el tamaño
  (`http.MaxBytesReader`), rechaza campos desconocidos (`DisallowUnknownFields`, así un
  error de tipeo en la app no pasa en silencio) y exige un único objeto JSON.

## Embedding en JSON

`ProgramProgressDetail` embebe a `ProgramProgress` (campo sin nombre). Al serializar,
`encoding/json` **aplana** los campos del embebido: el detalle tiene la misma forma que
un elemento de la lista, más `completed_session_ids`. Es composición, no herencia, pero
en el JSON se ve como un `extends`.

Se hizo así por un detalle de `omitempty`: omite los campos con valor cero, y para un
slice eso incluye el **vacío**, no solo el `nil`. Con un solo tipo y `omitempty`, una
Senda recién reseteada mandaba el campo ausente en vez de `[]`.

## Trampa con fechas: `Truncate` no da "hoy"

`time.Now().Truncate(24 * time.Hour)` trunca contra la medianoche **UTC**. En Córdoba
(UTC-3) eso es el día anterior a las 21:00, y si después se lee `.Day()` en la zona
local, da el día equivocado. "Hoy" para el usuario se arma con los componentes locales:
`time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)`. Salió de un test
de integración que fallaba solo de noche.

## SQL que vale la pena conocer

- **`left join lateral (...) on true`**: una subconsulta que se evalúa **por cada fila**
  de la consulta de afuera y puede usar sus columnas. Se usa para "la próxima Fragua sin
  check de cada Senda" en una sola consulta (sin N+1).
- **sqlc no ve la nulabilidad a través de una lateral**: tipa sus columnas como no
  nullable, y el `Scan` fallaría con un `NULL`. Se resuelve en el SQL con `coalesce` y
  un valor centinela (`0` = no hay próxima), documentado en la consulta.
- **`sqlc.narg(slug)`**: un parámetro nullable con nombre. `(sqlc.narg(slug)::text is
  null or p.slug = sqlc.narg(slug))` hace que la misma consulta sirva para la lista
  (`nil`) y para el detalle (un slug).
- **`insert ... on conflict do update`**: un *upsert*. Crea la fila o, si ya existe,
  la actualiza, de forma atómica.
