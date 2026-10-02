-- Consultas de lectura del catálogo (programas y sesiones).
--
-- Cada consulta lleva un comentario "-- name: <Función> <:one|:many>" que sqlc usa
-- para generar una función Go: :one devuelve una fila (o pgx.ErrNoRows si no hay),
-- :many devuelve un slice. Los parámetros posicionales ($1, $2...) pasan a ser
-- argumentos de la función, con el tipo de la columna con la que se comparan.

-- name: ListPrograms :many
-- Todos los programas, con la cantidad de sesiones de cada uno.
select p.id, p.slug, p.name, p.description,
       count(ps.session_id) as session_count
from program p
left join program_session ps on ps.program_id = p.id
group by p.id
order by p.id;

-- name: GetProgramBySlug :one
select id, slug, name, description
from program
where slug = $1;

-- name: ListProgramSessions :many
-- Las sesiones de un programa, en orden.
select ps.position, s.id, s.kind, s.title
from program_session ps
join session s on s.id = ps.session_id
where ps.program_id = $1
order by ps.position;

-- name: GetSession :one
select id, kind, title, description
from session
where id = $1;

-- name: ListSessionItems :many
-- Todos los ítems de una sesión en orden de ejecución, una fila por ítem con los
-- datos de su bloque repetidos: el código Go los agrupa en bloques. Es una sola
-- consulta en vez de una por bloque (el problema "N+1" de JPA).
-- El left join es porque los descansos no tienen ejercicio.
select i.id         as item_id,
       b.position   as block_position,
       b.type       as block_type,
       b.time_cap_s,
       i.round,
       i.position,
       i.kind,
       i.side,
       i.duration_s,
       i.reps,
       e.slug       as exercise_slug,
       e.name       as exercise_name
from block b
join block_item i     on i.block_id = b.id
left join exercise e  on e.id = i.exercise_id
where b.session_id = $1
order by b.position, i.round, i.position;

-- ── Ejercicio ───────────────────────────────────────────────────────────────

-- name: GetExerciseBySlug :one
select id, slug, name, unilateral, description
from exercise
where slug = $1;

-- name: ListExerciseVideos :many
-- Uno sin lado, o uno por lado (izquierdo primero: el orden del enum side).
select side, url
from exercise_video
where exercise_id = $1
order by side nulls first;

-- name: ListExerciseMuscles :many
select m.slug, m.name
from exercise_muscle em
join muscle m on m.id = em.muscle_id
where em.exercise_id = $1
order by m.name;

-- name: ListExerciseJoints :many
select j.slug, j.name
from exercise_joint ej
join joint j on j.id = ej.joint_id
where ej.exercise_id = $1
order by j.name;

-- name: ListExerciseProgressions :many
-- Los vecinos directos en el grafo de progresiones: de qué ejercicios se
-- llega a este (easier) y a cuáles se progresa desde este (harder).
-- sqlc.arg pone nombre al parámetro: se usa dos veces, y sin nombre sqlc lo
-- llamaría como la primera columna con la que se compara (HarderID), que
-- confunde.
select 'easier'::text as direction, e.slug, e.name
from exercise_progression p
join exercise e on e.id = p.easier_id
where p.harder_id = sqlc.arg(exercise_id)
union all
select 'harder'::text as direction, e.slug, e.name
from exercise_progression p
join exercise e on e.id = p.harder_id
where p.easier_id = sqlc.arg(exercise_id)
order by direction, name;
