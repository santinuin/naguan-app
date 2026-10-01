-- Cierra el acceso directo a las tablas por la API REST de Supabase.
--
-- Supabase expone el esquema public con PostgREST (/rest/v1), y los roles
-- anon (cualquiera con la clave publicable, que va dentro de la app) y
-- authenticated tienen permisos por defecto: sin esto, cualquiera podría leer
-- y modificar las tablas sin pasar por la API Go.
--
-- Naguan no usa PostgREST: todo acceso a datos pasa por la API Go, que se
-- conecta como postgres (dueño de las tablas, no sujeto a RLS). Por eso se
-- cierra todo, en dos capas:
--   1. RLS activada sin políticas: para anon y authenticated, cero filas.
--   2. Permisos revocados: ni siquiera pueden intentarlo.

alter table exercise             enable row level security;
alter table exercise_video       enable row level security;
alter table exercise_progression enable row level security;
alter table muscle               enable row level security;
alter table joint                enable row level security;
alter table exercise_muscle      enable row level security;
alter table exercise_joint       enable row level security;
alter table session              enable row level security;
alter table program              enable row level security;
alter table program_session      enable row level security;
alter table block                enable row level security;
alter table block_item           enable row level security;

revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke all on all functions in schema public from anon, authenticated;

-- Y para lo que se cree de acá en adelante: sin esto, cada tabla nueva
-- volvería a nacer con permisos para anon y authenticated.
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke all on functions from anon, authenticated;
