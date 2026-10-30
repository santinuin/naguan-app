-- Enfriá de 10 s entre las vueltas de un mismo ejercicio en el calentamiento
-- y la movilidad («Colgarse | 20s | x2»): sin él, la segunda vuelta arranca a
-- los 3 s de preparación. Es la misma regla que aplica el importador
-- (BuildPhases en backend/internal/mhimport/phases.go) desde ahora; esta
-- migración corrige los bloques que se cargaron antes.
--
-- Va como migración y no como seed: los seeds de las fases ya se aplicaron en
-- producción, y la CLI no vuelve a correr uno que cambió. En una base nueva
-- (supabase db reset) las migraciones corren antes de los seeds, con block
-- vacío: acá no hace nada, y los Enfriá los trae el seed regenerado.
--
-- Solo agrega filas al final de cada vuelta: los ítems que ya existen no
-- cambian de id ni de posición, y las Fraguas templadas que los referencian
-- (workout_item.block_item_id) quedan como estaban. Correrla dos veces no
-- duplica nada: un bloque que ya tiene un descanso no entra.

insert into block_item (block_id, round, position, kind, duration_s)
select bi.block_id, bi.round, max(bi.position) + 1, 'rest', 10
from block_item bi
join block b on b.id = bi.block_id
join (
  -- Bloques de un solo ejercicio (los dos lados de un unilateral cuentan como
  -- uno), con más de una vuelta y sin descansos.
  select block_id, max(round) as rounds
  from block_item
  group by block_id
  having count(distinct exercise_id) = 1
     and count(*) filter (where kind = 'rest') = 0
     and max(round) > 1
) single on single.block_id = bi.block_id
where b.phase <> 'main'
  and bi.round < single.rounds -- después de la última vuelta, no
group by bi.block_id, bi.round;
