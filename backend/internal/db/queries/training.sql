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
select i.id, i.kind, i.exercise_id, e.name as exercise_name
from block_item i
join block b on b.id = i.block_id
left join exercise e on e.id = i.exercise_id
where b.session_id = $1;

-- name: BestResults :many
-- Las mejores marcas previas del usuario en estos ejercicios (0 = sin marca).
-- coalesce porque max() de ninguna fila es null.
select bi.exercise_id::bigint as exercise_id,
       coalesce(max(wi.reps), 0)::int       as best_reps,
       coalesce(max(wi.duration_s), 0)::int as best_duration_s
from workout_item wi
join workout w     on w.id = wi.workout_id
join block_item bi on bi.id = wi.block_item_id
where w.user_id = @user_id
  and bi.exercise_id = any(@exercise_ids::bigint[])
group by bi.exercise_id;

-- name: CreateWorkout :one
insert into workout (user_id, session_id, started_at, finished_at, local_date)
values ($1, $2, $3, $4, $5)
returning id;

-- name: CreateWorkoutItems :copyfrom
-- Inserta muchas filas de una con el protocolo COPY de Postgres: mucho más
-- rápido que un INSERT por fila (el equivalente a un batch de JDBC).
insert into workout_item (workout_id, block_item_id, reps, duration_s)
values ($1, $2, $3, $4);

-- name: ListWorkouts :many
-- El historial del usuario, de lo más reciente a lo más viejo, con la Senda
-- de cada sesión (la primera, si una sesión estuviera en varias).
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
order by w.finished_at desc
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
-- Los Mojones: la mejor marca del usuario en cada ejercicio, juntando ambos
-- lados de los unilaterales (se agrupa por ejercicio, no por lado).
select e.slug, e.name,
       coalesce(max(wi.reps), 0)::int       as best_reps,
       coalesce(max(wi.duration_s), 0)::int as best_duration_s
from workout_item wi
join workout w     on w.id = wi.workout_id
join block_item bi on bi.id = wi.block_item_id
join exercise e    on e.id = bi.exercise_id
where w.user_id = @user_id
group by e.id
order by e.name;
