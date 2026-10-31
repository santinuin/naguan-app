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
order by p.position nulls last, p.id;

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
-- la app y para detectar Mojones (solo los de la fase 'main'). El tipo y la
-- posición del bloque y las reps del plan sirven para las pirámides: el pico
-- de un ejercicio es el peldaño más alto × su incremento (i.reps).
select i.id, i.kind, b.phase, b.type as block_type, b.position as block_position,
       i.reps as planned_reps, i.exercise_id, e.slug as exercise_slug, e.name as exercise_name
from block_item i
join block b on b.id = i.block_id
left join exercise e on e.id = i.exercise_id
where b.session_id = $1;

-- name: BestResults :many
-- Las mejores marcas previas del usuario en estos ejercicios (0 = sin marca).
-- coalesce porque max() de ninguna fila es null. Cuenta el ejercicio que se
-- hizo (wi.exercise_id), no el del bloque: pudo haberse cambiado. Solo
-- cuenta el entrenamiento: el calentamiento y la movilidad no son Mojones.
--
-- Las reps cuentan solo en las series sin carga (5 con la barra vacía no
-- empatan con 5 con 100 kg); con carga, el peso máximo y el 1RM estimado
-- (ver e1rm en ListRecords). "filter" es un where solo para ese agregado.
--
-- En una pirámide, wi.reps son las reps totales del bloque (no una serie):
-- no compiten por reps ni por 1RM. Su marca es el pico: el peldaño más alto
-- (workout_pyramid.peak) × el incremento del ejercicio (bi.reps).
select wi.exercise_id,
       coalesce(max(wi.reps) filter (where wi.load_kg is null and b.type <> 'pyramid'
                                     and wi.duration_s is null), 0)::int as best_reps,
       coalesce(max(wi.duration_s), 0)::int as best_duration_s,
       coalesce(max(wi.load_kg), 0)::float8 as best_load_kg,
       coalesce(max(round(wi.load_kg * (1 + wi.reps * 0.0333), 1))
                filter (where wi.reps > 0 and b.type <> 'pyramid'
                                and wi.duration_s is null), 0)::float8 as best_e1rm_kg,
       coalesce(max(wp.peak * bi.reps), 0)::int as best_peak_reps
from workout_item wi
join workout w     on w.id = wi.workout_id
join block_item bi on bi.id = wi.block_item_id
join block b       on b.id = bi.block_id
left join workout_pyramid wp on wp.workout_id = wi.workout_id and wp.block_position = b.position
                            and b.type = 'pyramid'
where w.user_id = @user_id
  and b.phase = 'main'
  and wi.exercise_id = any(@exercise_ids::bigint[])
group by wi.exercise_id;

-- name: ListExercisesBySlug :many
-- Los ejercicios que la app dice haber hecho en lugar de los del bloque (una
-- progresión más fácil o más difícil). Los slugs que no existen no vuelven:
-- así se detectan.
select id, slug, name from exercise where slug = any(@slugs::text[]);

-- name: CreateWorkout :one
insert into workout (user_id, session_id, started_at, finished_at, local_date, client_id, main_duration_s)
values ($1, $2, $3, $4, $5, $6, $7)
returning id;

-- name: GetSessionTimeRecord :one
-- El título de la sesión y si su Mojón es el menor tiempo, con la mejor
-- marca previa del usuario (0 = sin marca).
select s.title, s.time_record,
       coalesce((select min(w.main_duration_s) from workout w
                 where w.user_id = @user_id and w.session_id = s.id), 0)::int as best_time_s
from session s
where s.id = @session_id;

-- name: ListSessionTimeRecords :many
-- Los Mojones de las sesiones a tiempo: el menor tiempo del entrenamiento en
-- cada una, con el día en que se logró (la primera vez, si se igualó).
select distinct on (w.session_id)
       s.id as session_id, s.title, w.main_duration_s::int as time_s, w.local_date
from workout w
join session s on s.id = w.session_id
where w.user_id = @user_id and s.time_record and w.main_duration_s is not null
order by w.session_id, w.main_duration_s, w.finished_at;

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

-- name: ListSessionPyramidPositions :many
-- Las posiciones de las pirámides de una sesión: para validar lo que manda la
-- app.
select position from block where session_id = $1 and type = 'pyramid';

-- name: CreateWorkoutPyramids :copyfrom
insert into workout_pyramid (workout_id, block_position, peak, rung_sum)
values ($1, $2, $3, $4);

-- name: CreateWorkoutItems :copyfrom
-- Inserta muchas filas de una con el protocolo COPY de Postgres: mucho más
-- rápido que un INSERT por fila (el equivalente a un batch de JDBC).
insert into workout_item (workout_id, block_item_id, exercise_id, reps, duration_s, load_kg)
values ($1, $2, $3, $4, $5, $6);

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
-- viejo: la materia prima de la Brasa. Como en los Mojones, cuenta solo el
-- entrenamiento: una Fragua que es solo calentamiento o movilidad (una pausa
-- activa, el antes y el después de un deporte) no prende la Brasa.
select distinct w.local_date
from workout w
where w.user_id = @user_id and w.local_date <= @today
  and exists (select 1 from block b where b.session_id = w.session_id and b.phase = 'main')
order by w.local_date desc;

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
--
-- Solo el entrenamiento (fase 'main'): el calentamiento y la movilidad no
-- son Mojones. Métricas: reps (solo series sin carga), duration_s, load_kg
-- (el peso más alto) y e1rm_kg, el 1RM estimado con la fórmula del libro
-- Barra Libre (peso × reps × 0,0333 + peso), que compara series de distintas
-- reps: 3 × 105 kg (115,5) contra 5 × 100 kg (116,7).
--
-- En una pirámide, las reps de workout_item son las totales del bloque: no
-- cuentan como serie (reps, e1rm_kg); su marca es peak_reps, el peldaño más
-- alto × el incremento del ejercicio.
with result as (
  select wi.exercise_id,
         -- Una serie: ni las reps totales de una pirámide ni las contadas en
         -- un ítem por tiempo («swings en 1 minuto»).
         case when b.type <> 'pyramid' and wi.duration_s is null then wi.reps end as reps,
         wi.duration_s, wi.load_kg,
         case when b.type <> 'pyramid' and wi.duration_s is null
              then round(wi.load_kg * (1 + wi.reps * 0.0333), 1) end as e1rm_kg,
         wp.peak * bi.reps as peak_reps,
         w.local_date, w.finished_at
  from workout_item wi
  join workout w     on w.id = wi.workout_id
  join block_item bi on bi.id = wi.block_item_id
  join block b       on b.id = bi.block_id
  left join workout_pyramid wp on wp.workout_id = wi.workout_id and wp.block_position = b.position
                              and b.type = 'pyramid'
  where w.user_id = @user_id
    and b.phase = 'main'
),
best as (
  (select distinct on (exercise_id)
          exercise_id, 'reps'::text as metric, reps::float8 as value, local_date
     from result
    where reps > 0 and load_kg is null
    order by exercise_id, reps desc, finished_at)
  union all
  (select distinct on (exercise_id)
          exercise_id, 'duration_s'::text, duration_s::float8, local_date
     from result
    where duration_s > 0
    order by exercise_id, duration_s desc, finished_at)
  union all
  (select distinct on (exercise_id)
          exercise_id, 'load_kg'::text, load_kg::float8, local_date
     from result
    where load_kg > 0
    order by exercise_id, load_kg desc, finished_at)
  union all
  (select distinct on (exercise_id)
          exercise_id, 'e1rm_kg'::text, e1rm_kg::float8, local_date
     from result
    where e1rm_kg > 0
    order by exercise_id, e1rm_kg desc, finished_at)
  union all
  (select distinct on (exercise_id)
          exercise_id, 'peak_reps'::text, peak_reps::float8, local_date
     from result
    where peak_reps > 0
    order by exercise_id, peak_reps desc, finished_at)
)
select e.slug, e.name, b.metric, b.value, b.local_date
from best b
join exercise e on e.id = b.exercise_id
order by e.name, b.metric desc;

-- name: ListLastLoads :many
-- El último peso que el usuario usó en cada ejercicio: el más alto de la
-- última Fragua en la que lo hizo con carga. La app lo propone la próxima
-- vez. distinct on, como en ListRecords: por ejercicio, la primera fila
-- ordenando por la Fragua más reciente y, dentro de ella, por peso.
select distinct on (wi.exercise_id)
       e.slug, wi.load_kg::float8 as load_kg, w.local_date
from workout_item wi
join workout w  on w.id = wi.workout_id
join exercise e on e.id = wi.exercise_id
where w.user_id = @user_id
  and wi.load_kg is not null
order by wi.exercise_id, w.finished_at desc, wi.load_kg desc;
