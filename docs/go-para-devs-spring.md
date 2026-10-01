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
