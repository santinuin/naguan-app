# Backend (Go)

API de la app. Ver `/CLAUDE.md` en la raíz del repo para el contexto completo de
arquitectura y decisiones.

```bash
go run ./cmd/api      # API en :8080 (o $PORT), contra $DATABASE_URL o el Postgres local
go test ./...
sqlc generate         # regenera internal/db a partir de internal/db/queries/*.sql
```

Endpoints: `GET /health` (público) y, bajo `/v1` y con `Authorization: Bearer <token de
Supabase>`: `GET /me`, `GET /programs`, `GET /programs/{slug}`, `GET /sessions/{id}`.
Ver `/docs/autenticacion.md`. Configuración por entorno: ver `internal/config`.
La base local se levanta con `supabase start` desde la raíz (ver `/CLAUDE.md`).

## Importar los programas (`cmd/seed`)

Convierte el material de `docs/source/` (no versionado) en el seed del catálogo:
ejercicios, progresiones, músculos, programas y sesiones. El esquema está en
`/supabase/migrations/`.

```bash
go run ./cmd/seed names   # crea o completa seed/exercise_names.csv
go run ./cmd/seed sql     # genera /supabase/seed.sql (no versionado)
```

`seed/exercise_names.csv` es la **fuente de verdad de la identidad y el nombre** de cada
ejercicio: una fila por ejercicio del índice original (`source_id`), con el nombre y el
lado en el catálogo nuevo. Las filas con el mismo `name` son el mismo ejercicio (así se
fusionan los duplicados de coach y los pares izquierda/derecha). Se edita a mano;
`names` conserva las ediciones y solo agrega filas nuevas.

El importador corta con errores ante datos inconsistentes (nombres que chocan,
tiempo y reps a la vez, bloques sin tipo...). Los errores puntuales de la fuente se
corrigen de forma explícita en `cellFixes` (`internal/mhimport/source.go`).
