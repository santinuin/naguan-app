-- Pirámides con tope de tiempo: subir 1, 2, 3... reps hasta el máximo, bajar
-- hasta 1 y, si sobra tiempo, volver a subir, durante time_cap_s. Ver
-- docs/modelo-de-datos.md («Pirámides»).
--
-- Los ítems del bloque son el peldaño modelo: cada ejercicio con su
-- incremento como reps (1 en Desencadenado; 2 en la pirámide de swings y
-- thrusters de Efecto Kettlebell). El peldaño n pide n × reps de cada uno.

-- time_cap_s: en los AMRAP y en las pirámides, y solo en ellos.
alter table block drop constraint block_check;
alter table block add constraint block_time_cap_check
  check ((type in ('amrap', 'pyramid')) = (time_cap_s is not null));

-- Lo que se hizo en cada pirámide: el peldaño más alto (peak) y la suma de los
-- peldaños completados (rung_sum: 1+2+...+7+6+... ). Las reps de un ejercicio
-- salen de multiplicar por su incremento (block_item.reps). Como las vueltas
-- de un AMRAP (workout_amrap), va aparte de workout_item: una pirámide no es
-- una serie.
create table workout_pyramid (
  workout_id     bigint   not null references workout on delete cascade,
  -- El bloque se identifica por su posición en la sesión (única por sesión).
  block_position smallint not null check (block_position > 0),
  peak           smallint not null check (peak >= 0),
  rung_sum       integer  not null check (rung_sum >= peak),
  primary key (workout_id, block_position)
);

alter table workout_pyramid enable row level security;

-- ── Lo que ya estaba cargado ────────────────────────────────────────────────
-- En una base nueva (supabase db reset) esto corre antes de los seeds, sin
-- programas: no hace nada, y las pirámides las trae el seed regenerado.
--
-- Desencadenado (semanas 1 y 2): las escaleras fijas 1→7→1 pasan a pirámides
-- de 7 minutos. El Enfriá del final de cada escalera («después 60») queda en
-- un bloque propio, como después de un AMRAP: los ítems de la pirámide se
-- repiten, y un Enfriá adentro se repetiría también.
--
-- Efecto Kettlebell (semana 10): el AMRAP de 5 minutos con swings y thrusters
-- de a 2 pasa a pirámide (sus ítems ya son el peldaño modelo).
--
-- Cambia ítems que el historial podría referenciar: si alguien ya templó una
-- de estas sesiones, aborta sin tocar nada (todo es una transacción).
do $$
declare
  b    record;
  rest integer;
begin
  if exists (
    select 1 from workout w
    join program_session ps on ps.session_id = w.session_id
    join program p on p.id = ps.program_id
    join session s on s.id = w.session_id
    join block bl on bl.session_id = w.session_id
    where (p.slug = 'desencadenado' and bl.type = 'ladder')
       or (p.slug = 'efecto-kettlebell' and s.title = 'Pirámide' and bl.type = 'amrap')
  ) then
    raise exception 'hay Fraguas templadas en sesiones con pirámides: convertirlas a mano';
  end if;

  -- De la última a la primera de cada sesión: al insertar el bloque del
  -- Enfriá se corren los que siguen, y así no se mueve uno que falta
  -- convertir.
  for b in
    select bl.id, bl.session_id, bl.position
    from block bl
    join program_session ps on ps.session_id = bl.session_id
    join program p on p.id = ps.program_id
    where p.slug = 'desencadenado' and bl.type = 'ladder'
    order by bl.session_id, bl.position desc
  loop
    select duration_s into rest from block_item where block_id = b.id and kind = 'rest';
    delete from block_item where block_id = b.id and (round > 1 or kind = 'rest');
    update block_item set reps = 1 where block_id = b.id;
    update block set type = 'pyramid', time_cap_s = 420 where id = b.id;

    if rest is not null then
      -- En dos pasos, porque (session_id, position) es único y Postgres lo
      -- verifica fila por fila.
      update block set position = position + 1000
        where session_id = b.session_id and position > b.position;
      update block set position = position - 999
        where session_id = b.session_id and position > 1000;
      with nb as (
        insert into block (session_id, position, type, phase)
        values (b.session_id, b.position + 1, 'rounds_with_rest', 'main')
        returning id
      )
      insert into block_item (block_id, round, position, kind, duration_s)
      select id, 1, 1, 'rest', rest from nb;
    end if;
  end loop;

  update block bl set type = 'pyramid'
  from program_session ps
  join program p on p.id = ps.program_id
  join session s on s.id = ps.session_id
  where bl.session_id = ps.session_id
    and p.slug = 'efecto-kettlebell' and s.title = 'Pirámide' and bl.type = 'amrap';
end
$$;

-- Las descripciones que hablaban de la escalera fija.
update session s set description = regexp_replace(s.description,
    'El libro la pide durante 7 minutos:\s+ajustá el pico para llenarlos\.',
    'Son 7 minutos: cuando llegues a tu máximo, tocá BAJAR; si llegás a 1 antes de' || chr(10) ||
    'tiempo, la app vuelve a subir.')
from program_session ps
join program p on p.id = ps.program_id
where ps.session_id = s.id and p.slug = 'desencadenado';

update session s set description = regexp_replace(s.description,
    'La vuelta escrita es la primera\.',
    'La app sube de a dos y descansa sola lo que tardaste en el peldaño.')
from program_session ps
join program p on p.id = ps.program_id
where ps.session_id = s.id and p.slug = 'efecto-kettlebell' and s.title = 'Pirámide';
