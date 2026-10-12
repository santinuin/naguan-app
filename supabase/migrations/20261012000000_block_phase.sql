-- Fase de un bloque dentro de su sesión: calentamiento, entrenamiento o
-- movilidad. Las tres van en la misma sesión (se templan juntas, en una sola
-- Fragua), pero la app las muestra por separado y los Mojones solo cuentan
-- el entrenamiento: estirar 35 s en vez de 30 no es un récord.
--
-- El orden de los valores importa: un enum de Postgres se ordena en el orden
-- en que se declaró (warmup < main < mobility), no alfabéticamente.

create type block_phase as enum ('warmup', 'main', 'mobility');

-- Con default, las filas que ya existen quedan como 'main' sin un update
-- aparte (y desde Postgres 11 no reescribe la tabla).
alter table block add column phase block_phase not null default 'main';
