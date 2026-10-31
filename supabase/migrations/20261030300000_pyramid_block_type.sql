-- Un tipo de bloque nuevo: la pirámide con tope de tiempo (ver
-- 20261030310000_pyramids.sql).
--
-- Va sola en su archivo: Postgres no deja usar un valor nuevo de un enum en
-- la misma transacción que lo agrega, y la CLI de Supabase corre cada
-- migración en una transacción.
alter type block_type add value 'pyramid';
