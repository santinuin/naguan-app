-- Catálogo de ejercicios, sesiones y programas.
--
-- Identificadores en inglés; el vocabulario de la app (Senda = programa,
-- Fragua = sesión, Golpe = serie, Enfriá = descanso) es de la interfaz.

-- ── Ejercicios ──────────────────────────────────────────────────────────────

create type side as enum ('left', 'right');

create table exercise (
  id          bigint generated always as identity primary key,
  slug        text not null unique,
  name        text not null,
  -- Se hace de a un lado por vez. El lado concreto va en block_item.side.
  unilateral  boolean not null default false,
  description text,          -- Markdown
  met         numeric(4, 1) not null check (met > 0)
);

-- Un video, o uno por lado si el ejercicio es unilateral.
create table exercise_video (
  exercise_id bigint not null references exercise on delete cascade,
  side        side,
  url         text not null,
  unique nulls not distinct (exercise_id, side)
);

-- Grafo de progresiones: desde easier se progresa a harder.
create table exercise_progression (
  easier_id bigint not null references exercise on delete cascade,
  harder_id bigint not null references exercise on delete cascade,
  primary key (easier_id, harder_id),
  check (easier_id <> harder_id)
);

create table muscle (
  id   smallint generated always as identity primary key,
  slug text not null unique,
  name text not null
);

create table joint (
  id   smallint generated always as identity primary key,
  slug text not null unique,
  name text not null
);

create table exercise_muscle (
  exercise_id bigint   not null references exercise on delete cascade,
  muscle_id   smallint not null references muscle,
  primary key (exercise_id, muscle_id)
);

create table exercise_joint (
  exercise_id bigint   not null references exercise on delete cascade,
  joint_id    smallint not null references joint,
  primary key (exercise_id, joint_id)
);

-- ── Sesiones y programas ────────────────────────────────────────────────────

create type session_kind as enum ('workout', 'warmup', 'mobility', 'cooldown');

-- Entidad propia: puede usarse suelta (p. ej. solo un calentamiento) o
-- dentro de uno o varios programas.
create table session (
  id          bigint generated always as identity primary key,
  kind        session_kind not null default 'workout',
  title       text not null,
  description text
);

create table program (
  id          bigint generated always as identity primary key,
  slug        text not null unique,
  name        text not null,
  description text
);

create table program_session (
  program_id bigint   not null references program on delete cascade,
  position   smallint not null check (position > 0),
  session_id bigint   not null references session,
  primary key (program_id, position)
);

create type block_type as enum (
  'rounds',            -- vueltas lo más rápido posible, sin descansos programados
  'rounds_with_rest',  -- vueltas con descansos programados
  'tabata',            -- trabajo y descanso fijos (típicamente 20 s / 10 s)
  'superset',          -- ejercicios encadenados sin pausa entre ellos
  'ladder',            -- escalera: las reps cambian vuelta a vuelta
  'amrap'              -- todas las vueltas posibles dentro de time_cap_s
);

create table block (
  id         bigint generated always as identity primary key,
  session_id bigint     not null references session on delete cascade,
  position   smallint   not null check (position > 0),
  type       block_type not null,
  -- Solo amrap tiene tope; sus ítems describen una vuelta que se repite.
  time_cap_s integer check (time_cap_s > 0),
  unique (session_id, position),
  check ((type = 'amrap') = (time_cap_s is not null))
);

create type item_kind as enum ('exercise', 'rest');

-- Desplegado: una fila por ejercicio y por vuelta, en orden de ejecución.
create table block_item (
  id          bigint    generated always as identity primary key,
  block_id    bigint    not null references block on delete cascade,
  round       smallint  not null check (round > 0),
  position    smallint  not null check (position > 0),
  kind        item_kind not null,
  exercise_id bigint references exercise,
  side        side,
  duration_s  integer  check (duration_s > 0),
  reps        smallint check (reps > 0),
  unique (block_id, round, position),
  check (
    (kind = 'rest'
      and exercise_id is null and side is null and reps is null
      and duration_s is not null)
    or
    (kind = 'exercise'
      and exercise_id is not null
      -- Se mide por tiempo o por repeticiones, nunca por ambos.
      and (duration_s is null) <> (reps is null))
  )
);

create index on block_item (exercise_id);
create index on program_session (session_id);
