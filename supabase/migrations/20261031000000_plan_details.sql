-- Detalles del plan que los programas piden y el modelo no tenía (ver
-- docs/limitaciones-del-modelo.md). Solo agrega columnas, con valores por
-- defecto que dejan todo como estaba: los programas ya cargados se completan
-- con un seed de actualización que genera el importador (ver
-- backend/README.md, «Actualizar lo que ya está cargado»).

-- Rangos de repeticiones («3 tandas de 5-8»): reps es el máximo (como hasta
-- ahora) y reps_min el mínimo. Null: un número fijo.
--
-- El "reps_min is null or" no sobra: un check solo rechaza si la condición da
-- falso. Sin él, en un descanso (reps null) "reps is not null" da falso, y
-- "null and falso" también: rechazaría todas las filas que ya existen.
alter table block_item add column reps_min smallint
  check (reps_min is null or (reps_min > 0 and reps is not null and reps_min < reps));

-- Máximo posible («todas las que puedas», «al fallo», «el máximo tiempo
-- posible»): reps o duration_s pasan a ser una referencia. En un ítem por
-- tiempo, la app cuenta hacia arriba en vez de hacia atrás.
alter table block_item add column open boolean not null default false;

-- Un ítem por tiempo que además cuenta las reps («todos los swings que
-- puedas en un minuto»): al terminar el tiempo, la app las pregunta.
alter table block_item add column count_reps boolean not null default false;
alter table block_item add constraint block_item_count_reps_check
  check (not count_reps or duration_s is not null);

-- Un bloque opcional («ejercicio extra: solo si te quedan fuerzas»): antes de
-- empezarlo, la app ofrece terminar ahí.
alter table block add column optional boolean not null default false;

-- Una indicación para el momento («2 s de subida y 2 de bajada», «la subida,
-- explosiva»): la app la muestra durante el bloque.
alter table block add column note text;

-- Sesiones que se hacen lo más rápido posible («anotá el tiempo: es tu marca a
-- batir»): su Mojón es el menor tiempo del entrenamiento.
alter table session add column time_record boolean not null default false;

-- Cuánto duró el entrenamiento (la fase main, sin calentamiento ni
-- movilidad), en segundos: lo mide la app. Null en las Fraguas anteriores o
-- de una app vieja.
alter table workout add column main_duration_s integer check (main_duration_s > 0);
