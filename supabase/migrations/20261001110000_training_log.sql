-- Datos del usuario: lo que entrena.
--
-- El modelo es flexible a propósito: el usuario puede templar cualquier
-- Fragua (sesión) de cualquier Senda (programa), en cualquier orden y las
-- veces que quiera. Cada Fragua templada es un workout; todo lo demás se
-- deriva de ahí:
--   - el progreso de cada Senda (qué Fraguas tienen check y cuál sigue),
--   - la Brasa (racha de días),
--   - los Mojones (récords por ejercicio).
--
-- Los usuarios viven en auth.users (lo administra Supabase Auth); acá se los
-- referencia por su id, el mismo "sub" del token. on delete cascade: si se
-- borra la cuenta, se borra todo lo suyo.

-- Una Fragua templada: una sesión completada por un usuario.
create table workout (
  id          bigint generated always as identity primary key,
  user_id     uuid   not null references auth.users on delete cascade,
  session_id  bigint not null references session,
  started_at  timestamptz not null,
  finished_at timestamptz not null,
  -- El día en la zona horaria del usuario, tal como lo ve el teléfono. Para
  -- la Brasa lo que importa es el día local: una Fragua a las 23:30 en
  -- Córdoba es "hoy", aunque en UTC ya sea mañana.
  local_date  date   not null,
  check (finished_at >= started_at)
);

-- El historial se lee siempre por usuario, de lo más reciente a lo más viejo.
create index workout_user_recent on workout (user_id, finished_at desc);
create index on workout (session_id);

-- Lo que el usuario hizo en cada ejercicio de la Fragua: las reps o los
-- segundos reales (pueden diferir de lo indicado). Solo ítems de ejercicio,
-- no descansos (lo valida la API). De acá salen los Mojones.
create table workout_item (
  workout_id    bigint not null references workout on delete cascade,
  block_item_id bigint not null references block_item,
  reps          smallint check (reps >= 0),
  duration_s    integer  check (duration_s >= 0),
  primary key (workout_id, block_item_id),
  check (reps is not null or duration_s is not null)
);
create index on workout_item (block_item_id);

-- El último reset de una Senda: los checks de sus Fraguas solo cuentan los
-- workouts posteriores. Resetear NO borra el historial (la Brasa y los
-- Mojones siguen intactos): solo mueve esta fecha. Una fila por usuario y
-- programa; sin fila, nunca se reseteó.
create table program_reset (
  user_id    uuid   not null references auth.users on delete cascade,
  program_id bigint not null references program,
  reset_at   timestamptz not null default now(),
  primary key (user_id, program_id)
);

-- Igual que el catálogo: sin acceso por la API REST de Supabase (ver la
-- migración lock_down_rest_api).
alter table workout       enable row level security;
alter table workout_item  enable row level security;
alter table program_reset enable row level security;
