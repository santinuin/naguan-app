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
`POST|GET /me/workouts`, `GET /me/stats?today=`, `GET /me/records`.
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

### Programas transcriptos a mano (`plans`)

Los planes de Fitness Revolucionario vienen en PDF: no hay un Excel con una fila
por vuelta. Se transcriben a un archivo de texto que describe los bloques **como los
escribe el libro** («3 tandas de 8, 1 minuto entre tandas»), y `internal/planimport`
los despliega al modelo: una fila por ejercicio, por lado y por vuelta, con los Enfriá
en su lugar. El formato está explicado en `internal/planimport/plan.go`:

- `= N | Título | CAL MOV` abre la sesión N, con sus plantillas de calentamiento y de
  movilidad (`@CAL`, `@MOV…`, definidas antes con los mismos bloques).
  `= N | copia de M` repite la sesión M (semanas iguales).
- Bloques: `vueltas xN`, `superset xN`, `pirámide 1-7-1` (escalera de reps) y
  `tabata x8 20/10`, con `| entre S` (Enfriá entre vueltas) y `| después S`
  (Enfriá antes del bloque siguiente). Una línea por ejercicio (`Nombre | 8r` o
  `| 60s`; sin medida en pirámides y tabatas), o `Enfriá | 20s`, hasta `end`.
- `>` agrega texto a la descripción del programa o de la sesión (Markdown).

Cada plan tiene dos archivos (ver `plans` en `cmd/seed/main.go`):

- **La transcripción**, en `docs/source/` (no versionada: es contenido del libro).
  Hoy: `Programas/Desencadenado /desencadenado.txt`. Su encabezado anota las
  decisiones de carga (rangos, pirámides, niveles), que siguen a
  `/docs/limitaciones-del-modelo.md`.
- **Lo que suma al catálogo**, en `seed/<programa>_catalogo.txt` (versionado: el
  texto es propio): ejercicios que el índice no tiene (`+ Nombre | MET [| unilateral]`
  y su descripción) y cadenas de progresión (`progresión: A > B > C`, los niveles
  del libro). Desencadenado suma 26 ejercicios, sin video.

Los nombres se resuelven contra el catálogo de `mhimport` (más «Colgarse», que crea
el seed de fases, y los ejercicios nuevos del plan); uno que no existe corta con
error. El SQL va por slugs, sin IDs, como el de las fases, porque se aplica también
sobre la base de producción, y aborta si el programa ya está cargado. En local:
`supabase db reset` lo carga último (ver `sql_paths`), o se aplica sobre la base que
ya está, sin perder usuarios ni Fraguas:

```bash
docker exec -i supabase_db_naguan-app psql -U postgres -v ON_ERROR_STOP=1 < ../supabase/seed_desencadenado.sql
```
