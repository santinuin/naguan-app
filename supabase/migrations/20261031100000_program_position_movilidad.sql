-- Las Sendas de movilidad (Pausas activas, Pádel y Fútbol) van después de
-- Barra Libre, en las posiciones 10 a 12, y los programas de prioridad baja
-- bajan al final. position es única: hay que liberar esos lugares antes de
-- que los seeds de las Sendas nuevas los ocupen (en producción, las
-- migraciones corren antes que los seeds). Mismo orden que programOrder en
-- backend/cmd/seed.

update program p set position = o.position
from (values
  ('elite', 13),
  ('primal', 14),
  ('aurum', 15)
) as o (slug, position)
where p.slug = o.slug;
