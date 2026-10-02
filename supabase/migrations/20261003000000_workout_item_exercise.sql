-- El ejercicio que el usuario hizo de verdad en cada ítem de una Fragua.
--
-- Antes de empezar, la app permite cambiar un ejercicio por una progresión
-- más fácil o más difícil (dominada → dominada asistida). El ítem del bloque
-- sigue siendo el mismo (block_item_id), pero el ejercicio ya no es el del
-- bloque: sin esta columna, las reps de la dominada asistida contarían como
-- Mojón de la dominada.
--
-- Se agrega en tres pasos porque la tabla ya tiene filas: una columna
-- "not null" nueva no puede quedar vacía en las existentes.

-- 1. La columna, todavía nullable.
alter table workout_item add column exercise_id bigint references exercise;

-- 2. Las filas existentes se completan con el ejercicio del bloque (hasta
--    hoy, siempre fue ese). "update ... from" es el join de un update.
update workout_item wi
   set exercise_id = bi.exercise_id
  from block_item bi
 where bi.id = wi.block_item_id;

-- 3. Ahora sí, obligatoria.
alter table workout_item alter column exercise_id set not null;

-- Los Mojones agrupan y filtran por ejercicio.
create index on workout_item (exercise_id);
