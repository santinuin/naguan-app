-- Orden de las Sendas en la app. Hasta ahora salían por id (el orden en que se
-- cargaron); ahora, por position. Los que no tienen posición van al final
-- (nulls last en las consultas), así un programa nuevo no rompe nada aunque su
-- seed no la traiga.
--
-- Los importadores (backend/cmd/seed, programOrder) escriben la misma posición
-- al cargar, para que una base nueva (supabase db reset: las migraciones corren
-- antes de los seeds, con program vacío, y estos update no hacen nada) salga
-- igual. Para reordenar después: una migración como esta y el mismo cambio en
-- programOrder.

alter table program add column position smallint unique;

update program p set position = o.position
from (values
  ('unbreakable', 1),
  ('ring-master', 2),
  ('desencadenado', 3),
  ('efecto-kettlebell', 4),
  ('barra-libre-1', 5),
  ('barra-libre-1-intermedio', 6),
  ('barra-libre-2', 7),
  ('barra-libre-3', 8),
  ('barra-libre-4', 9),
  ('elite', 10),
  ('primal', 11),
  ('aurum', 12)
) as o (slug, position)
where p.slug = o.slug;
