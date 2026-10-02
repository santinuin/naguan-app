-- Corrige el sentido de las progresiones cargadas con el seed anterior.
--
-- El índice de ejercicios de MH tiene las columnas "Más fácil" / "Más difícil"
-- rotuladas al revés, y el importador las leía al pie de la letra: todas las
-- aristas de exercise_progression quedaron invertidas (Flexión → "más
-- difícil": Flexión con rodillas). El importador ya las lee cruzadas
-- (backend/internal/mhimport/source.go).
--
-- Esta migración invierte las aristas que ya existen. En una base nueva
-- (`supabase db reset`) corre antes del seed, con la tabla vacía: no hace nada,
-- y el seed regenerado carga el sentido correcto.

-- Una sola sentencia: el CTE borra las aristas y devuelve las borradas
-- (`returning`), y el insert las vuelve a cargar dadas vuelta. Es atómica
-- aunque la migración no corra dentro de una transacción.
with old as (
  delete from exercise_progression
  returning easier_id, harder_id
)
insert into exercise_progression (easier_id, harder_id)
  select harder_id, easier_id from old;
