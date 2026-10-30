package planimport

import (
	"bufio"
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/santinuin/naguan-app/backend/internal/mhimport"
)

// RenderSQL escribe el seed de un programa nuevo. Sirve igual para la base
// local (después de seed.sql y de los de fases) que para la de producción,
// que ya tiene el catálogo y Fraguas templadas de otros programas.
//
// No lleva IDs: cada ejercicio se busca por slug. Si un slug no existe, el
// subselect da null y lo corta un not null o el check de block_item. Se
// aplica una sola vez: si el programa ya existe, aborta sin cambiar nada
// (todo va en una transacción).
func RenderSQL(out io.Writer, p *Program) error {
	w := &writer{w: bufio.NewWriter(out)}
	w.printf("-- Generado por backend/cmd/seed (comando plans). No editar a mano:\n")
	w.printf("-- corregí la transcripción y volvé a generar.\n\nbegin;\n")

	// Los ejercicios nuevos, con on conflict: si ya existen (los creó otro
	// plan), quedan como están.
	for _, e := range p.NewExercises {
		w.printf("\ninsert into exercise (slug, name, unilateral, description, met)\n")
		w.printf("  values (%s, %s, %t, %s, %s)\n  on conflict (slug) do nothing;\n",
			str(e.Slug), str(e.Name), p.Unilateral[e.Slug], str(e.Description),
			strconv.FormatFloat(e.MET, 'f', -1, 64))
	}

	// Las progresiones: si el par ya existía (vino del índice), no se repite.
	if len(p.Progressions) > 0 {
		w.printf("\ninsert into exercise_progression (easier_id, harder_id) values\n")
		for i, pr := range p.Progressions {
			w.printf("  (%s, %s)%s\n", exerciseID(pr[0]), exerciseID(pr[1]), sep(i, len(p.Progressions), ""))
		}
		w.printf("  on conflict do nothing;\n")
	}

	// Un bloque DO es un pedazo de PL/pgSQL anónimo: permite variables, if y
	// raise, que el SQL plano no tiene.
	w.printf("\ndo $$\ndeclare\n  p bigint; -- programa\n  s bigint; -- sesión\n  b bigint; -- bloque\nbegin\n")
	w.printf("  if exists (select 1 from program where slug = %s) then\n", str(p.Slug))
	w.printf("    raise exception '%s ya está cargado';\n  end if;\n", p.Slug)
	w.printf("  insert into program (slug, name, description)\n    values (%s, %s, %s) returning id into p;\n",
		str(p.Slug), str(p.Name), nullStr(p.Description))

	for i, s := range p.Sessions {
		w.printf("\n  -- Sesión %d: %s\n", i+1, s.Title)
		w.printf("  insert into session (title, description) values (%s, %s) returning id into s;\n",
			str(s.Title), nullStr(s.Description))
		w.printf("  insert into program_session (program_id, position, session_id) values (p, %d, s);\n", i+1)
		for j, b := range s.Blocks {
			w.block(j+1, b)
		}
	}
	w.printf("end\n$$;\n\ncommit;\n")
	return w.flush()
}

func (w *writer) block(position int, b Block) {
	w.printf("  insert into block (session_id, position, type, phase)\n")
	w.printf("    values (s, %d, '%s', '%s') returning id into b;\n", position, b.Type, b.Phase)
	w.printf("  insert into block_item (block_id, round, position, kind, exercise_id, side, duration_s, reps) values\n")
	for i, it := range b.Items {
		end := sep(i, len(b.Items), ";")
		if it.Rest {
			w.printf("    (b, %d, %d, 'rest', null, null, %d, null)%s\n", it.Round, it.Position, it.DurationS, end)
			continue
		}
		w.printf("    (b, %d, %d, 'exercise', %s, %s, %s, %s)%s\n",
			it.Round, it.Position, exerciseID(it.ExerciseSlug), side(it.Side),
			optInt(it.DurationS), optInt(it.Reps), end)
	}
}

// sep es el separador de la fila i de n: una coma, salvo en la última.
func sep(i, n int, last string) string {
	if i == n-1 {
		return last
	}
	return ","
}

func exerciseID(slug string) string {
	return fmt.Sprintf("(select id from exercise where slug = %s)", str(slug))
}

func optInt(v int) string {
	if v == 0 {
		return "null"
	}
	return strconv.Itoa(v)
}

// str escapa un texto como literal de SQL estándar: la única secuencia
// especial es la comilla simple, que se duplica.
func str(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }

func nullStr(s string) string {
	if s == "" {
		return "null"
	}
	return str(s)
}

func side(s mhimport.Side) string {
	if s == mhimport.SideNone {
		return "null"
	}
	return str(string(s))
}

// writer guarda el primer error de escritura, así el resto del código no
// tiene que chequear cada llamada (el mismo patrón que en mhimport).
type writer struct {
	w   *bufio.Writer
	err error
}

func (w *writer) printf(format string, args ...any) {
	if w.err == nil {
		_, w.err = fmt.Fprintf(w.w, format, args...)
	}
}

func (w *writer) flush() error {
	if w.err != nil {
		return w.err
	}
	return w.w.Flush()
}
