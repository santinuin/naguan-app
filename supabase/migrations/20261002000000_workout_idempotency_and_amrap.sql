-- Dos agregados al registro de Fraguas:
--
-- 1. Idempotencia: la app genera un id único (client_id) por Fragua. Si el
--    registro se reintenta (sin señal, o se perdió la respuesta aunque el
--    servidor lo había guardado), el mismo client_id no crea un duplicado:
--    la API devuelve el que ya existía.
--
-- 2. Vueltas de los AMRAP: cuántas vueltas completó el usuario en cada bloque
--    AMRAP. Van en su propia tabla y no en workout_item: las reps de un AMRAP
--    no son "una serie", y mezclarlas arruinaría los Mojones.

alter table workout add column client_id uuid;

-- Único por usuario. Un índice único admite varios null: los workouts sin
-- client_id (registrados antes de este cambio) no chocan entre sí.
create unique index workout_client_id_per_user on workout (user_id, client_id);

create table workout_amrap (
  workout_id     bigint   not null references workout on delete cascade,
  -- El bloque se identifica por su posición en la sesión (única por sesión).
  block_position smallint not null check (block_position > 0),
  rounds         smallint not null check (rounds >= 0),
  primary key (workout_id, block_position)
);

alter table workout_amrap enable row level security;
