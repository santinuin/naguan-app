-- Consultas del registro de entrenamiento. Todas filtran por user_id: un
-- usuario nunca ve ni toca datos de otro, y el user_id sale siempre del token
-- verificado.
--
-- Regla del progreso de una Senda: una Fragua "tiene check" si el usuario la
-- templó al menos una vez DESPUÉS del último reset de esa Senda (o alguna vez,
-- si nunca la reseteó).

-- name: ListProgramProgress :many
-- Todas las Sendas con el progreso del usuario y la próxima Fragua sugerida
-- (la primera, por posición, sin check). El "left join lateral" es una
-- subconsulta que se evalúa por cada programa y puede usar sus columnas
-- (p.id): como un for anidado dentro del SQL.
select p.id, p.slug, p.name,
       (select count(*) from program_session ps where ps.program_id = p.id) as total_sessions,
       (select count(distinct w.session_id)
          from workout w
          join program_session ps on ps.session_id = w.session_id and ps.program_id = p.id
         where w.user_id = @user_id
           and (r.reset_at is null or w.finished_at > r.reset_at)) as completed_sessions,
       r.reset_at,
       -- Con la Senda completa, la lateral no trae filas y estas columnas
       -- serían null. sqlc no puede deducir eso a través de una lateral (las
       -- tipa como no nullable y el Scan fallaría), así que se convierten a
       -- un valor centinela: 0 = no hay próxima Fragua.
       coalesce(nxt.position, 0)::smallint as next_position,
       coalesce(nxt.id, 0)::bigint         as next_session_id,
       coalesce(nxt.title, '')::text       as next_title
from program p
left join program_reset r on r.program_id = p.id and r.user_id = @user_id
left join lateral (
  select ps.position, s.id, s.title
  from program_session ps
  join session s on s.id = ps.session_id
  where ps.program_id = p.id
    and not exists (
      select 1 from workout w
      where w.user_id = @user_id and w.session_id = ps.session_id
        and (r.reset_at is null or w.finished_at > r.reset_at)
    )
  order by ps.position
  limit 1
) nxt on true
where (sqlc.narg(slug)::text is null or p.slug = sqlc.narg(slug))
order by p.id;

-- name: ListCompletedSessions :many
-- Los ids de las Fraguas con check de una Senda.
select distinct w.session_id
from workout w
join program_session ps on ps.session_id = w.session_id and ps.program_id = @program_id
left join program_reset r on r.program_id = @program_id and r.user_id = w.user_id
where w.user_id = @user_id
  and (r.reset_at is null or w.finished_at > r.reset_at)
order by w.session_id;

-- name: ResetProgramProgress :exec
-- "Upsert": crea la fila, o si ya existe, actualiza la fecha.
insert into program_reset (user_id, program_id, reset_at)
values ($1, $2, now())
on conflict (user_id, program_id) do update set reset_at = excluded.reset_at;

-- name: ListSessionItemsForWorkout :many
-- Los ítems de una sesión con su tipo y ejercicio: para validar lo que manda
-- la app y para detectar Mojones.
select i.id, i.kind, i.exercise_id, e.slug as exercise_slug, e.name as exercise_name
from block_item i
join block b on b.id = i.block_id
left join exercise e on e.id = i.exercise_id
where b.session_id = $1;

-- name: BestResults :many
-- Las mejores marcas previas del usuario en estos ejercicios (0 = sin marca).
-- coalesce porque max() de ninguna fila es null. Cuenta el ejercicio que se
-- hizo (wi.exercise_id), no el del bloque: pudo haberse cambiado.
select wi.exercise_id,
       coalesce(max(wi.reps), 0)::int       as best_reps,
       coalesce(max(wi.duration_s), 0)::int as best_duration_s
from workout_item wi
join workout w on w.id = wi.workout_id
where w.user_id = @user_id
  and wi.exercise_id = any(@exercise_ids::bigint[])
group by wi.exercise_id;

-- name: ListExercisesBySlug :many
-- Los ejercicios que la app dice haber hecho en lugar de los del bloque (una
-- progresión más fácil o más difícil). Los slugs que no existen no vuelven:
-- así se detectan.
select id, slug, name from exercise where slug = any(@slugs::text[]);

-- name: CreateWorkout :one
insert into workout (user_id, session_id, started_at, finished_at, local_date, client_id)
values ($1, $2, $3, $4, $5, $6)
returning id;

-- name: GetWorkoutIDByClientID :one
-- Para la idempotencia: el id del workout que el usuario ya registró con
-- este client_id, si existe.
select id from workout where user_id = $1 and client_id = $2;

-- name: GetWorkout :one
-- Un workout del usuario, con la misma forma que el historial.
select w.id, w.session_id, s.title as session_title,
       coalesce(prog.slug, '')::text as program_slug,
       coalesce(prog.name, '')::text as program_name,
       w.started_at, w.finished_at, w.local_date
from workout w
join session s on s.id = w.session_id
left join lateral (
  select p.slug, p.name
  from program_session ps
  join program p on p.id = ps.program_id
  where ps.session_id = w.session_id
  order by p.id
  limit 1
) prog on true
where w.user_id = @user_id and w.id = @id;

-- name: ListSessionAmrapPositions :many
-- Las posiciones de los bloques AMRAP de una sesión: para validar las
-- vueltas que manda la app.
select position from block where session_id = $1 and type = 'amrap';

-- name: CreateWorkoutAmraps :copyfrom
insert into workout_amrap (workout_id, block_position, rounds)
values ($1, $2, $3);

-- name: CreateWorkoutItems :copyfrom
-- Inserta muchas filas de una con el protocolo COPY de Postgres: mucho más
-- rápido que un INSERT por fila (el equivalente a un batch de JDBC).
insert into workout_item (workout_id, block_item_id, exercise_id, reps, duration_s)
values ($1, $2, $3, $4, $5);

-- name: ListWorkouts :many
-- El historial del usuario, de lo más reciente a lo más viejo, con la Senda
-- de cada sesión (la primera, si una sesión estuviera en varias).
--
-- Paginación por cursor (keyset): la página siguiente pide "las anteriores
-- al workout @before", el último que la app ya tiene. Se compara el par
-- (finished_at, id) y no solo finished_at: dos Fraguas podrían terminar en
-- el mismo instante, y el id desempata para que ninguna se repita ni se
-- pierda entre páginas. A diferencia de offset ("saltear 40"), no se corre
-- si entra una Fragua nueva mientras se pagina, y usa el índice
-- workout_user_recent en vez de leer y descartar las filas salteadas.
--
-- Si @before no es un workout del usuario, la subconsulta da null, la
-- comparación también, y la página sale vacía.
select w.id, w.session_id, s.title as session_title,
       -- Una sesión suelta (sin Senda) no trae filas en la lateral: '' en
       -- vez de null, por lo mismo que en ListProgramProgress.
       coalesce(prog.slug, '')::text as program_slug,
       coalesce(prog.name, '')::text as program_name,
       w.started_at, w.finished_at, w.local_date
from workout w
join session s on s.id = w.session_id
left join lateral (
  select p.slug, p.name
  from program_session ps
  join program p on p.id = ps.program_id
  where ps.session_id = w.session_id
  order by p.id
  limit 1
) prog on true
where w.user_id = @user_id
  and (sqlc.narg(before)::bigint is null
       or (w.finished_at, w.id) < (select c.finished_at, c.id
                                     from workout c
                                    where c.user_id = @user_id and c.id = sqlc.narg(before)))
order by w.finished_at desc, w.id desc
limit @max_rows;

-- name: ListTrainingDays :many
-- Los días (locales) en que el usuario entrenó, del más reciente al más
-- viejo: la materia prima de la Brasa.
select distinct local_date
from workout
where user_id = @user_id and local_date <= @today
order by local_date desc;

-- name: CountWorkouts :one
select count(*) from workout where user_id = $1;

-- name: ListRecords :many
-- Los Mojones: la mejor marca del usuario en cada ejercicio (juntando ambos
-- lados de los unilaterales), una fila por ejercicio y métrica, con el día
-- en que la logró por primera vez.
--
-- Con max() + group by sale el valor, pero no el día: max() no dice de qué
-- fila salió. "distinct on (exercise_id)" (propio de Postgres) se queda con
-- la PRIMERA fila de cada ejercicio según el order by: ordenando por valor
-- descendente y después por fecha, esa fila es la marca y el día en que se
-- alcanzó (si se igualó después, cuenta la primera vez).
--
-- Los "with" (CTE) son subconsultas con nombre: se leen de arriba abajo,
-- como variables intermedias.
with result as (
  select wi.exercise_id, wi.reps, wi.duration_s, w.local_date, w.finished_at
  from workout_item wi
  join workout w on w.id = wi.workout_id
  where w.user_id = @user_id
),
best as (
  (select distinct on (exercise_id)
          exercise_id, 'reps'::text as metric, reps::int as value, local_date
     from result
    where reps > 0
    order by exercise_id, reps desc, finished_at)
  union all
  (select distinct on (exercise_id)
          exercise_id, 'duration_s'::text, duration_s::int, local_date
     from result
    where duration_s > 0
    order by exercise_id, duration_s desc, finished_at)
)
select e.slug, e.name, b.metric, b.value, b.local_date
from best b
join exercise e on e.id = b.exercise_id
order by e.name, b.metric desc;
