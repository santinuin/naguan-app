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
go run ./cmd/seed phases  # genera /supabase/seed_phases.sql (no versionado)
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
(`phaseNewExercises`, hoy solo «Colgarse»). Un nombre sin resolver corta con error.

`supabase db reset` lo carga después de `seed.sql` (ver `sql_paths` en
`supabase/config.toml`). Para producción, ver `docs/despliegue.md`.

