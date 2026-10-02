# Modelo de datos

Cómo está organizada la base de Naguan y por qué. El esquema vive en
`supabase/migrations/` (se aplica en orden); acá están las decisiones de diseño.

## Vista general

```
CATÁLOGO (contenido, igual para todos)            ENTRENAMIENTO (de cada usuario)

program ──< program_session >── session           auth.users (Supabase Auth)
                                   │                  │
                                   └──< block         ├──< program_reset ──> program
                                          │           │       (último reset de una Senda)
                                          └──< block_item     │
                                                 │    └──< workout ──> session
exercise ──< exercise_video                      │           │  (Fragua templada)
    │   ──< exercise_progression >──             │           └──< workout_item
    │   ──< exercise_muscle >── muscle           │                  │
    │   ──< exercise_joint  >── joint            │                  │
    └──────────────────────────< ─────────────── ┘ <────────────────┘
                                   (block_item.exercise_id) (workout_item.block_item_id)
```

`A ──< B` significa "un A tiene muchos B".

## Catálogo

### Ejercicios

- **`exercise` no tiene lado.** "Plancha lateral (derecha)" y "(izquierda)" son el mismo
  ejercicio: `unilateral = true`, y el lado concreto va en cada ítem de una sesión
  (`block_item.side`). En el catálogo aparece una sola "Plancha lateral".
- **`exercise_video`**: uno, o uno por lado cuando la fuente tiene un video para cada
  lado. `unique nulls not distinct (exercise_id, side)` impide dos videos para el mismo
  lado, incluido el lado null (sin el `nulls not distinct`, Postgres considera que dos
  null son distintos y permitiría duplicados).
- **`exercise_progression`** es un grafo: de `easier_id` se progresa a `harder_id`. Viene
  de las columnas "más fácil / más difícil" del índice original, que están **rotuladas al
  revés** (Flexión → "Más Fácil": Flexión diamante). El importador las lee cruzadas, y la
  migración `20261002100000_fix_progression_direction.sql` dio vuelta las aristas que ya
  estaban cargadas. En las variantes numeradas de las anillas, 1 es la más fácil.
  `GET /v1/exercises/{slug}` devuelve los vecinos directos (`easier` / `harder`).
- **Músculos y articulaciones** son tablas propias con tablas de unión, no arrays: así se
  puede consultar "todos los ejercicios de glúteos" con un join y un índice.

### Sesiones y programas

- **La sesión es independiente del programa.** `program_session` dice en qué posición
  aparece cada sesión en cada programa. Así una sesión (por ejemplo, un calentamiento) se
  puede usar suelta o en varios programas.
- **`block_item` está desplegado**: una fila por ejercicio **y por vuelta**, en orden de
  ejecución. Guardar "plantilla × N vueltas" no alcanza: hay escaleras (reps que bajan
  vuelta a vuelta) y descansos distintos en la última vuelta. Desplegado, ejecutar una
  sesión es recorrer una lista. Son ~7.000 filas: nada para Postgres.
- **El descanso es un ítem (`kind = 'rest'`), no un ejercicio.** Un `check` garantiza que
  un descanso no tenga ejercicio ni reps, y que un ejercicio se mida por tiempo **o** por
  reps, nunca por ambos. La regla vive en la base, no solo en el código.
- **`amrap`** es el único bloque con `time_cap_s`: sus ítems describen una vuelta que se
  repite hasta que se acaba el tiempo. Otro `check` liga las dos cosas.

## Entrenamiento

### La idea: todo se deriva de lo que entrenaste

El modelo es flexible a propósito. Cada usuario templa **cualquier Fragua de cualquier
Senda, en cualquier orden y las veces que quiera**: hay quien sigue el orden del
programa, quien repite una Fragua varios días seguidos y quien salta entre programas. Lo
importante es entrenar.

Por eso hay una sola fuente de verdad, **`workout`** (cada Fragua templada), y todo lo
demás se calcula:

| Qué | Cómo se deriva |
|---|---|
| **Check** de una Fragua en una Senda | Se templó al menos una vez después del último reset de esa Senda |
| **Próxima Fragua sugerida** | La primera, por posición, sin check |
| **Progreso** de una Senda | Cantidad de Fraguas distintas con check / total |
| **Brasa** (racha) | Los días distintos (`local_date`) con al menos una Fragua |
| **Mojones** (récords) | La mejor marca en `workout_item` por ejercicio |

Guardar cualquiera de esas cosas (un "puntero a la próxima", un contador de racha) sería
duplicar información que se puede desincronizar. Calculada, siempre es correcta. Una
versión anterior del diseño tenía una "Senda activa" única por usuario; se descartó por
rígida.

### `workout`: cada Fragua templada

- `user_id` referencia a `auth.users`: los usuarios los administra Supabase Auth, y su
  `id` es el `sub` del token. `on delete cascade`: si se borra la cuenta, se borra todo lo
  suyo.
- **`local_date`**: el día en el teléfono del usuario. La Brasa depende del día *local*:
  una Fragua a las 23:30 en Córdoba es "hoy", aunque en UTC ya sea mañana. Guardar el día
  que ve el usuario evita calcular zonas horarias en el servidor. La API valida que no
  difiera en más de un día de `finished_at`.
- `started_at` y `finished_at` son `timestamptz` (un instante, sin ambigüedad). La API
  los devuelve siempre en UTC; cada cliente los muestra en su zona horaria.

### `workout_item`: lo que se hizo en cada ejercicio

- Las reps o los segundos **reales**, que pueden diferir de lo indicado en la sesión.
- Solo ítems de ejercicio de **esa** sesión: lo valida la API dentro de la transacción
  (un ítem de otra sesión o un descanso se rechaza con 400).

### Idempotencia: `workout.client_id`

Cada Fragua lleva un UUID que genera el teléfono. Hay un índice único por
`(user_id, client_id)`: si la app reintenta el registro (sin señal, o se perdió la
respuesta aunque el servidor lo había guardado), el mismo `client_id` no crea un
duplicado y la API devuelve el existente (200 en vez de 201). Si dos reintentos llegan a
la vez, la base lo detecta (violación de la restricción única) y se devuelve el que ganó.
Los workouts anteriores a este cambio tienen `client_id` null (un índice único admite
varios null).

### `workout_amrap`: las vueltas de los AMRAP

Cuántas vueltas completó el usuario en cada bloque AMRAP, por posición del bloque. Van en
su propia tabla y no en `workout_item`: las reps de un AMRAP no son "una serie", y
mezclarlas arruinaría los Mojones.

### `program_reset`: empezar una Senda de cero

Una fila por usuario y Senda con la fecha del último reset. Los checks solo cuentan los
workouts posteriores. **Resetear no borra nada**: el historial, la Brasa y los Mojones
siguen intactos; solo cambia desde cuándo se cuentan los checks. Es un *upsert*
(`insert ... on conflict do update`): la primera vez crea la fila, las siguientes
actualizan la fecha.

### La Brasa

Cuenta los **días en que entrenaste** y se apaga con **dos días hábiles seguidos sin
entrenar**:

- Se puede parar un día hábil y la Brasa sigue encendida.
- Sábado y domingo son opcionales: si entrenás, suman; si no, no cuentan como falta.
  (Por eso faltar viernes y lunes son dos faltas seguidas y la apagan.)
- Hoy nunca cuenta como falta: el día no terminó.
- **En riesgo** (`at_risk`): ya faltaste un día hábil y hoy (hábil) todavía no
  entrenaste. Es el momento de «No la dejes apagar».

La regla vive en una función pura (`training/brasa.go`) con un test por caso sobre un
calendario concreto. La app manda su "hoy" (`GET /v1/me/stats?today=AAAA-MM-DD`), porque
el servidor no sabe en qué zona horaria está el teléfono.

### Los Mojones

- Uno por ejercicio, **juntando ambos lados** de los unilaterales: la mejor cantidad de
  reps en una serie y/o la mayor duración sostenida (una plancha).
- Al registrar una Fragua, la respuesta trae `new_records` con los Mojones superados y la
  marca anterior, para que la app lo celebre.
- **La primera vez** que se hace un ejercicio no es Mojón (no había marca que superar);
  igualar tampoco. Hay Mojón cuando se supera.

## Seguridad: la base no se expone

Supabase publica el esquema `public` por su API REST (PostgREST), y la clave publicable
(que va dentro de la app) da acceso a los roles `anon` y `authenticated`. Sin protección,
cualquiera podría leer y **modificar** las tablas sin pasar por la API Go. Lo comprobamos:
un `PATCH` anónimo a `program` respondía 200.

La migración `lock_down_rest_api` cierra eso en dos capas:

1. **Row Level Security activada sin políticas** en todas las tablas: para `anon` y
   `authenticated`, cero filas.
2. **Permisos revocados**, incluidos los *default privileges*: las tablas que se creen en
   el futuro tampoco nacen con permisos para esos roles.

La API Go se conecta como `postgres`, el dueño de las tablas, que no está sujeto a RLS.
**La autorización la hace Go**: cada consulta del usuario filtra por el `user_id` del
token verificado, y las rutas del usuario van bajo `/v1/me/...` (no existe un
`/v1/users/{id}` donde alguien pueda poner otro id).

**Regla para migraciones nuevas:** toda tabla nueva lleva `enable row level security`.

## Cómo se carga

- El esquema: `supabase/migrations/*.sql`, en orden, con `supabase db reset` (desde cero)
  o `supabase migration up` (solo las nuevas).
- El catálogo: `supabase/seed.sql`, generado por `backend/cmd/seed` a partir de los
  Excel (ver `backend/README.md`). No se versiona: tiene contenido de la fuente.
- Los datos de entrenamiento los crea la app a través de la API.
