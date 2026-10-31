# Backend (Go)

API de la app. Ver `/CLAUDE.md` en la raíz del repo para el contexto completo de
arquitectura y decisiones.

```bash
go run ./cmd/api      # API en :8080 (o $PORT), contra $DATABASE_URL o el Postgres local
go test ./...         # + TEST_DATABASE_URL=... para los tests de integración
sqlc generate         # regenera internal/db a partir de internal/db/queries/*.sql
```

Endpoints: `GET /health` (público) y, bajo `/v1` y con `Authorization: Bearer <token de
Supabase>`: `GET /programs`, `GET /programs/{slug}`, `GET /sessions/{id}`, `GET /exercises/{slug}` y, del usuario, `GET /me`,
`GET /me/programs[/{slug}]`, `DELETE /me/programs/{slug}/progress`,
`POST|GET /me/workouts`, `GET /me/stats?today=`, `GET /me/records`, `GET /me/loads`.
Ver `/docs/autenticacion.md`. Configuración por entorno: ver `internal/config`.
La base local se levanta con `supabase start` desde la raíz (ver `/CLAUDE.md`).

## Importar los programas (`cmd/seed`)

Convierte el material de `docs/source/` (no versionado) en el seed del catálogo:
ejercicios, progresiones, músculos, programas y sesiones. El esquema está en
`/supabase/migrations/`.

```bash
go run ./cmd/seed names   # crea o completa seed/exercise_names.csv
go run ./cmd/seed sql     # genera /supabase/seed.sql (no versionado)
go run ./cmd/seed phases  # genera /supabase/seed_phases*.sql (no versionados)
go run ./cmd/seed plans   # genera /supabase/seed_<programa>.sql (no versionados)
go run ./cmd/seed plans barra-libre   # … solo el de ese programa
```

`seed/exercise_names.csv` es la **fuente de verdad de la identidad y el nombre** de cada
ejercicio: una fila por ejercicio del índice original (`source_id`), con el nombre y el
lado en el catálogo nuevo. Las filas con el mismo `name` son el mismo ejercicio (así se
fusionan los duplicados de coach y los pares izquierda/derecha). Se edita a mano;
`names` conserva las ediciones y solo agrega filas nuevas.

El importador corta con errores ante datos inconsistentes (nombres que chocan,
tiempo y reps a la vez, bloques sin tipo...). Los errores puntuales de la fuente se
corrigen de forma explícita en `cellFixes` (`internal/mhimport/source.go`).

### Calentamiento y movilidad (`phases`)

Los programas de Mammoth Hunters traen solo el entrenamiento. El calentamiento y la
movilidad de Unbreakable se transcribieron a mano de capturas de la app original, en
`docs/source/Programas/Unbreakable/calentamiento_y_movilidad.txt` (no versionado):
plantillas de ejercicios (`@CAL01`, `@MOV01`...) y qué plantilla usa cada sesión. El
formato está explicado al principio del archivo y en `internal/mhimport/phases.go`.

`phases` lo convierte en `/supabase/seed_phases.sql`: un bloque `rounds` por grupo de
ejercicios, con `phase` `warmup` o `mobility`. Los nombres de las capturas que no
coinciden con el catálogo se traducen en `phaseAliases` (la app original decía
"hombros" donde el índice dice "deltoides"); los que no existen en el índice se crean
(`PhaseNewExercises`, hoy solo «Colgarse»). Un nombre sin resolver corta con error.
Un bloque de un solo ejercicio con varias vueltas («Colgarse | 20s | x2») lleva un
Enfriá de 10 s (`PhaseRestS`) entre vuelta y vuelta; lo cargado antes de esa regla lo
corrige la migración `20261030000000_phase_rests.sql`.

El calentamiento y la movilidad de **Ring Master** también se perdieron con la app
original, pero no hay capturas: son una reconstrucción propia en
`seed/ring_master_fases.txt` (mismo formato; versionado, porque no es contenido de la
fuente). El criterio (calentamiento RAMP, estiramientos con carga en anillas al final)
y qué plantilla va con cada tipo de sesión están en el encabezado del archivo.

Cada programa genera su propio archivo (`phasePrograms` en `cmd/seed/main.go`):
`seed_phases.sql` (Unbreakable) y `seed_phases_ring_master.sql`. Van separados porque
la CLI de Supabase aplica cada seed una sola vez y lo reconoce por su hash: sumar un
programa no puede cambiar el archivo de otro que ya está en producción.

`supabase db reset` los carga después de `seed.sql` (ver `sql_paths` en
`supabase/config.toml`). Para producción, ver `docs/despliegue.md`.


### Títulos de las sesiones (`titles`)

La fuente deja muchas sesiones como "Sesión N". `seed/session_titles.csv` (versionado,
como el de ejercicios: solo nombres) les da un nombre por programa y posición; hoy, las
de Unbreakable, por tipo y en orden ("Fuerza 3", "Flow 7"), según la descripción y la
etiqueta de cada semana del plan original. `sql` los usa al generar `seed.sql`.

Para producción, `go run ./cmd/seed titles` imprime un `UPDATE` (por programa y
posición, se puede correr las veces que haga falta) para pegar en el editor SQL de
Supabase. No es un archivo de seed: la CLI no vuelve a correr un seed ya aplicado que
cambió, solo le actualiza el hash.

### Orden de las Sendas (`programOrder`)

`programOrder` (en `cmd/seed/main.go`) es el orden en que la app muestra las Sendas:
`sql` y `plans` escriben esa posición en `program.position`. Un programa que no está
en la lista queda sin posición, al final. Reordenar es editar la lista **y** sumar una
migración que actualice la base que ya existe (los seeds no se vuelven a aplicar en
producción); ver `20261030100000_program_position.sql`.

### Programas transcriptos a mano (`plans`)

Los planes de Fitness Revolucionario vienen en PDF: no hay un Excel con una fila
por vuelta. Se transcriben a un archivo de texto que describe los bloques **como los
escribe el libro** («3 tandas de 8, 1 minuto entre tandas»), y `internal/planimport`
los despliega al modelo: una fila por ejercicio, por lado y por vuelta, con los Enfriá
en su lugar. El formato está explicado en `internal/planimport/plan.go`:

- `= N | Título | CAL MOV` abre la sesión N, con sus plantillas de calentamiento y de
  movilidad (`@CAL`, `@MOV…`, definidas antes con los mismos bloques).
  `= N | copia de M` repite la sesión M (semanas iguales).
- Bloques: `vueltas xN`, `superset xN`, `pirámide 1-7-1` (escalera fija de reps),
  `pirámide 420s` (pirámide con tope de tiempo: los ítems son el peldaño modelo, con el
  incremento como reps, `Flexión | 1r`), `tabata x8 20/10` (con `alterna`, un
  ejercicio distinto por vuelta) y `amrap 300` (tope en segundos), con `| entre S`
  (Enfriá entre vueltas) y `| después S` (Enfriá antes del bloque siguiente; en un
  AMRAP o una pirámide con tope, en un bloque aparte). Una línea por ejercicio
  (`Nombre | 8r` o `| 60s`; sin medida en las escaleras fijas y los tabatas), o
  `Enfriá | 20s`, hasta `end`. Un unilateral se hace por los dos lados, salvo que
  la línea termine en `| der`, `| izq` o `| alternando` (un solo paso sin lado).
- Detalles: un rango (`Flexión | 5-8r`), el máximo posible (`Dominada | 8r | máx`), un
  ítem por tiempo que cuenta reps (`Swing | 60s | cuenta`; en un tabata, `Burpee |
  cuenta`), un bloque opcional (`vueltas x2 | opcional`), una nota para el momento
  (líneas `nota: ...` al principio del bloque) y una sesión a tiempo (`marca: tiempo`,
  después de su encabezado).
- `video: Nombre | url` da el video de un ejercicio nuevo del plan (va en la
  transcripción, no versionada, porque los links son de la fuente).
- `aproximación [corta] Ejercicio`: las series de aproximación antes de las de trabajo
  (5-5-5-3-2, o 5-3-2), con sus Enfriá. `pirámide 15,9,6`: las reps de cada vuelta.
- `incluir otro.txt` trae las plantillas y los videos de otro archivo (las cinco Sendas
  de Barra Libre comparten `barra_libre_comun.txt`), y `usar NOMBRE` mete los bloques
  de una plantilla en el entrenamiento de una sesión (los HIIT, los complejos).
- `>` agrega texto a la descripción del programa o de la sesión (Markdown).

Cada plan tiene dos archivos (ver `plans` en `cmd/seed/main.go`):

- **La transcripción**, en `docs/source/` (no versionada: es contenido del libro).
  Hoy: `Programas/Desencadenado /desencadenado.txt`,
  `Programas/Efecto Kettlebell/efecto_kettlebell.txt` y `Programas/Barra Libre/`
  (`barra_libre_1.txt`, `_1_intermedio`, `_2`, `_3`, `_4` y el común). Su encabezado anota las
  decisiones de carga (rangos, pirámides, niveles), que siguen a
  `/docs/limitaciones-del-modelo.md`.
- **Lo que suma al catálogo**, en `seed/<programa>_catalogo.txt` (versionado: el
  texto es propio): ejercicios que el índice no tiene (`+ Nombre | MET [| unilateral]`
  y su descripción) y cadenas de progresión (`progresión: A > B > C`, los niveles
  del libro). Desencadenado suma 26 ejercicios, sin video; Efecto Kettlebell, 22
  movimientos con kettlebell, 15 de ellos con el video del libro; Barra Libre, 17
  movimientos con barra (11 con video), en un archivo que comparten sus cinco Sendas.

Un plan puede usar los ejercicios nuevos de otro (los HIIT de Barra Libre usan los
swings de Efecto Kettlebell): los conoce, pero no los inserta, así que su seed va
después en `sql_paths` (y en producción, se aplica después).

Los nombres se resuelven contra el catálogo de `mhimport` (más «Colgarse», que crea
el seed de fases, y los ejercicios nuevos del plan); uno que no existe corta con
error. El SQL va por slugs, sin IDs, como el de las fases, porque se aplica también
sobre la base de producción, y aborta si el programa ya está cargado.

**Al sumar un programa, generá solo ese** (`plans <slug>`). Sin argumentos, `plans`
reescribe los archivos de todos: si un cambio en el importador cambia el texto del SQL
de un programa que ya está en producción (aunque dé los mismos datos), le cambia el
hash, y el próximo `db push --include-seed` lo marca para actualizar el hash (no lo
vuelve a correr). Pasó con Desencadenado al sumar la columna `time_cap_s`, el
2026-10-30. En local:
`supabase db reset` lo carga último (ver `sql_paths`), o se aplica sobre la base que
ya está, sin perder usuarios ni Fraguas:

```bash
docker exec -i supabase_db_naguan-app psql -U postgres -v ON_ERROR_STOP=1 < ../supabase/seed_desencadenado.sql
```

### Actualizar lo que ya está cargado (`plans-update`)

Un seed se aplica una sola vez. Cuando el modelo suma un campo del plan (un rango, un
bloque opcional...), los programas que ya están en producción no lo traen, y volver a
cargarlos no se puede (las Fraguas templadas apuntan a sus ítems). Para eso:

```bash
go run ./cmd/seed plans-update desencadenado   # genera /supabase/seed_desencadenado_detalles.sql
```

El SQL no inserta ni borra nada: busca cada sesión por programa y posición, cada bloque
por posición y cada ítem por vuelta y posición, y actualiza solo las columnas de los
detalles. Antes verifica que la base tenga la misma estructura que la transcripción
(cuántos bloques e ítems); si no, aborta sin cambiar nada. Correrlo dos veces deja lo
mismo. Para producción se aplica como un seed nuevo (ver `docs/despliegue.md`). Cada
actualización necesita un archivo con otro nombre (la CLI no vuelve a correr uno que
ya aplicó): `-tag` cambia el sufijo, p. ej. `go run ./cmd/seed -tag aproximacion
plans-update barra-libre-1` (las notas de las series de aproximación, 2026-10-31).
