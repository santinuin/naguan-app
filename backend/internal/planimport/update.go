package planimport

import (
	"bufio"
	"io"
)

// RenderUpdateSQL escribe el SQL que completa, en un programa que ya está
// cargado, los detalles que RenderSQL inserta al crearlo: rangos, máximos,
// ítems que cuentan reps, bloques opcionales, notas y sesiones a tiempo.
//
// Hace falta porque un seed se aplica una sola vez: cuando el modelo suma un
// campo, los programas que ya estaban en producción no lo traen. Este SQL no
// inserta ni borra nada (los ids no cambian, así que las Fraguas templadas
// siguen apuntando a lo mismo): busca cada sesión por programa y posición,
// cada bloque por posición y cada ítem por vuelta y posición, y actualiza
// solo esas columnas.
//
// Antes de tocar nada verifica que la estructura de la base sea la de la
// transcripción (cuántos bloques tiene cada sesión y cuántos ítems cada
// bloque); si no coincide, aborta sin cambiar nada (todo va en una
// transacción). Correrlo dos veces deja lo mismo.
func RenderUpdateSQL(out io.Writer, p *Program) error {
	w := &writer{w: bufio.NewWriter(out)}
	w.printf("-- Generado por backend/cmd/seed (comando plans-update). No editar a mano:\n")
	w.printf("-- corregí la transcripción y volvé a generar.\n\nbegin;\n")
	w.printf("\ndo $$\ndeclare\n  s bigint; -- sesión\n  b bigint; -- bloque\n  n int;    -- conteo para verificar la estructura\nbegin\n")

	for i, s := range p.Sessions {
		pos := i + 1
		w.printf("\n  -- Sesión %d: %s\n", pos, s.Title)
		// "into strict" lanza un error si no hay exactamente una fila: si la
		// sesión no existe, se aborta todo.
		w.printf("  select ps.session_id into strict s from program_session ps\n")
		w.printf("    join program p on p.id = ps.program_id where p.slug = %s and ps.position = %d;\n", str(p.Slug), pos)
		w.printf("  select count(*) into n from block where session_id = s;\n")
		w.printf("  if n <> %d then raise exception 'sesión %d: la base tiene %% bloques y la transcripción %d', n; end if;\n",
			len(s.Blocks), pos, len(s.Blocks))
		if s.TimeRecord {
			w.printf("  update session set time_record = true where id = s;\n")
		}
		for j, b := range s.Blocks {
			bpos := j + 1
			w.printf("  select id into strict b from block where session_id = s and position = %d;\n", bpos)
			w.printf("  select count(*) into n from block_item where block_id = b;\n")
			w.printf("  if n <> %d then raise exception 'sesión %d, bloque %d: la base tiene %% ítems y la transcripción %d', n; end if;\n",
				len(b.Items), pos, bpos, len(b.Items))
			if b.Optional || b.Note != "" {
				w.printf("  update block set optional = %t, note = %s where id = b;\n", b.Optional, nullStr(b.Note))
			}
			for _, it := range b.Items {
				if it.RepsMin == 0 && !it.Open && !it.CountReps {
					continue
				}
				w.printf("  update block_item set reps_min = %s, open = %t, count_reps = %t\n",
					optInt(it.RepsMin), it.Open, it.CountReps)
				w.printf("    where block_id = b and round = %d and position = %d;\n", it.Round, it.Position)
			}
		}
	}
	w.printf("end\n$$;\n\ncommit;\n")
	return w.flush()
}
