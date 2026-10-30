package mhimport

import (
	"bufio"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// batchSize es cuántas filas van en cada INSERT. Un INSERT con miles de
// VALUES funciona, pero en lotes los errores de Postgres señalan una zona
// chica del archivo.
const batchSize = 500

// RenderSQL escribe el seed completo: un INSERT por tabla, en orden de
// dependencias, dentro de una transacción. Los IDs van explícitos
// (OVERRIDING SYSTEM VALUE) para que el archivo sea determinista; al final
// se ajustan las secuencias para que los próximos INSERT sigan desde ahí.
func RenderSQL(out io.Writer, cat *Catalog, programs []*Program) error {
	w := &sqlWriter{w: bufio.NewWriter(out)}
	w.printf("-- Generado por backend/cmd/seed. No editar a mano: corregí el CSV de\n")
	w.printf("-- nombres o la fuente y volvé a generar.\n\nbegin;\n")

	lookupRows := func(ls []Lookup) [][]string {
		rows := make([][]string, len(ls))
		for i, l := range ls {
			rows[i] = []string{num(l.ID), str(l.Slug), str(l.Name)}
		}
		return rows
	}
	w.insert("muscle", []string{"id", "slug", "name"}, lookupRows(cat.Muscles))
	w.insert("joint", []string{"id", "slug", "name"}, lookupRows(cat.Joints))

	muscleID, jointID := lookupIDs(cat.Muscles), lookupIDs(cat.Joints)
	var exRows, videoRows, emRows, ejRows [][]string
	for _, e := range cat.Exercises {
		exRows = append(exRows, []string{
			num(e.ID), str(e.Slug), str(e.Name), strconv.FormatBool(e.Unilateral),
			nullStr(e.Description), strconv.FormatFloat(e.MET, 'f', -1, 64),
		})
		for _, side := range []Side{SideNone, SideLeft, SideRight} {
			if url, ok := e.Videos[side]; ok {
				videoRows = append(videoRows, []string{num(e.ID), sideSQL(side), str(url)})
			}
		}
		for _, m := range e.Muscles {
			emRows = append(emRows, []string{num(e.ID), num(muscleID[m])})
		}
		for _, j := range e.Joints {
			ejRows = append(ejRows, []string{num(e.ID), num(jointID[j])})
		}
	}
	w.insert("exercise", []string{"id", "slug", "name", "unilateral", "description", "met"}, exRows)
	w.insert("exercise_video", []string{"exercise_id", "side", "url"}, videoRows)
	w.insert("exercise_muscle", []string{"exercise_id", "muscle_id"}, emRows)
	w.insert("exercise_joint", []string{"exercise_id", "joint_id"}, ejRows)

	var progRows [][]string
	for _, p := range cat.Progressions {
		progRows = append(progRows, []string{num(p.EasierID), num(p.HarderID)})
	}
	w.insert("exercise_progression", []string{"easier_id", "harder_id"}, progRows)

	var pRows, sRows, psRows, bRows, iRows [][]string
	var blockID, itemID int64
	for _, p := range programs {
		pRows = append(pRows, []string{num(p.ID), str(p.Slug), str(p.Name), "null"})
		for i, s := range p.Sessions {
			sRows = append(sRows, []string{num(s.ID), str(s.Title), nullStr(s.Description)})
			psRows = append(psRows, []string{num(p.ID), strconv.Itoa(i + 1), num(s.ID)})
			for j, b := range s.Blocks {
				blockID++
				timeCap := "null"
				if b.TimeCapS > 0 {
					timeCap = strconv.Itoa(b.TimeCapS)
				}
				bRows = append(bRows, []string{num(blockID), num(s.ID), strconv.Itoa(j + 1), str(b.Type), timeCap})
				for _, it := range b.Items {
					itemID++
					iRows = append(iRows, itemRow(itemID, blockID, it))
				}
			}
		}
	}
	w.insert("program", []string{"id", "slug", "name", "description"}, pRows)
	w.insert("session", []string{"id", "title", "description"}, sRows)
	w.insert("program_session", []string{"program_id", "position", "session_id"}, psRows)
	w.insert("block", []string{"id", "session_id", "position", "type", "time_cap_s"}, bRows)
	w.insert("block_item", []string{"id", "block_id", "round", "position", "kind",
		"exercise_id", "side", "duration_s", "reps"}, iRows)

	// Solo las tablas con identity: las de unión no tienen secuencia. Va en
	// un bloque DO con PERFORM para no imprimir un resultado por tabla.
	w.printf("\ndo $$\nbegin\n")
	for _, t := range []string{"muscle", "joint", "exercise", "program", "session", "block", "block_item"} {
		w.printf("  perform setval(pg_get_serial_sequence('%s', 'id'), coalesce(max(id), 1)) from %s;\n", t, t)
	}
	w.printf("end\n$$;\n")
	w.printf("\ncommit;\n")
	return w.flush()
}

func itemRow(id, blockID int64, it Item) []string {
	optInt := func(v int) string {
		if v == 0 {
			return "null"
		}
		return strconv.Itoa(v)
	}
	if it.Rest {
		return []string{num(id), num(blockID), strconv.Itoa(it.Round), strconv.Itoa(it.Position),
			"'rest'", "null", "null", strconv.Itoa(it.DurationS), "null"}
	}
	return []string{num(id), num(blockID), strconv.Itoa(it.Round), strconv.Itoa(it.Position),
		"'exercise'", num(it.Exercise.ExerciseID), sideSQL(it.Exercise.Side),
		optInt(it.DurationS), optInt(it.Reps)}
}

func lookupIDs(ls []Lookup) map[string]int64 {
	m := make(map[string]int64, len(ls))
	for _, l := range ls {
		m[l.Slug] = l.ID
	}
	return m
}

// sqlWriter guarda el primer error de escritura, así el resto del código no
// tiene que chequear cada llamada (el patrón de bufio.Writer y de
// text/tabwriter).
type sqlWriter struct {
	w   *bufio.Writer
	err error
}

func (s *sqlWriter) printf(format string, args ...any) {
	if s.err == nil {
		_, s.err = fmt.Fprintf(s.w, format, args...)
	}
}

func (s *sqlWriter) insert(table string, cols []string, rows [][]string) {
	for start := 0; start < len(rows); start += batchSize {
		batch := rows[start:min(start+batchSize, len(rows))]
		// Los IDs explícitos en una columna identity requieren OVERRIDING
		// SYSTEM VALUE; las tablas de unión no tienen identity.
		override := ""
		if cols[0] == "id" {
			override = " overriding system value"
		}
		s.printf("\ninsert into %s (%s)%s values\n", table, strings.Join(cols, ", "), override)
		for i, r := range batch {
			sep := ","
			if i == len(batch)-1 {
				sep = ";"
			}
			s.printf("  (%s)%s\n", strings.Join(r, ", "), sep)
		}
	}
}

func (s *sqlWriter) flush() error {
	if s.err != nil {
		return s.err
	}
	return s.w.Flush()
}

func num(v int64) string { return strconv.FormatInt(v, 10) }

// str escapa un texto como literal de SQL estándar: la única secuencia
// especial es la comilla simple, que se duplica.
func str(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }

func nullStr(s string) string {
	if s == "" {
		return "null"
	}
	return str(s)
}

func sideSQL(s Side) string {
	if s == SideNone {
		return "null"
	}
	return str(string(s))
}

// RenderPhasesSQL escribe el SQL que agrega el calentamiento y la movilidad
// a las sesiones de un programa que ya está cargado: sirve igual para la
// base local (después de seed.sql) que para la de producción, donde hay
// Fraguas templadas que no se pueden tocar.
//
// Por eso, a diferencia de RenderSQL, no lleva IDs explícitos: la sesión se
// busca por programa y posición, y cada ejercicio por slug. Si un slug no
// existe, el subselect da null y el check de block_item corta todo.
//
// Se aplica una sola vez: si el programa ya tiene bloques que no son de
// entrenamiento, aborta sin cambiar nada (todo va en una transacción).
func RenderPhasesSQL(out io.Writer, programSlug string, sessions []SessionPhases) error {
	w := &sqlWriter{w: bufio.NewWriter(out)}
	w.printf("-- Generado por backend/cmd/seed (comando phases). No editar a mano:\n")
	w.printf("-- corregí la transcripción y volvé a generar.\n\nbegin;\n")

	// Los ejercicios que el índice original no tiene. Con on conflict: si
	// ya existen (el script se corrió antes), el error lo da la
	// verificación de abajo, que es más clara.
	for _, e := range phaseNewExercises {
		w.printf("\ninsert into exercise (slug, name, unilateral, description, met)\n")
		w.printf("  values (%s, %s, false, %s, %s)\n  on conflict (slug) do nothing;\n",
			str(e.Slug), str(e.Name), str(e.Description), strconv.FormatFloat(e.MET, 'f', -1, 64))
	}

	// Un bloque DO es un pedazo de PL/pgSQL anónimo: permite variables,
	// if y raise, que el SQL plano no tiene.
	w.printf("\ndo $$\ndeclare\n  s bigint;   -- sesión\n  b bigint;   -- bloque recién insertado\n  m smallint; -- última posición ocupada\nbegin\n")
	w.printf("  if exists (\n    select 1 from block bl\n    join program_session ps on ps.session_id = bl.session_id\n")
	w.printf("    join program p on p.id = ps.program_id\n    where p.slug = %s and bl.phase <> 'main'\n  ) then\n", str(programSlug))
	w.printf("    raise exception '%s ya tiene calentamiento o movilidad cargados';\n  end if;\n", programSlug)

	for _, s := range sessions {
		w.printf("\n  -- Sesión %d\n", s.Position)
		w.printf("  select ps.session_id into strict s from program_session ps\n")
		w.printf("    join program p on p.id = ps.program_id\n    where p.slug = %s and ps.position = %d;\n", str(programSlug), s.Position)

		if n := len(s.Warmup); n > 0 {
			// El calentamiento va primero: los bloques que ya están se
			// corren n lugares. En dos pasos, porque (session_id, position)
			// es único y Postgres lo verifica fila por fila: sumar n de una
			// podría chocar con un bloque que todavía no se movió. Lo mismo
			// con las vueltas de los AMRAP, que guardan la posición del bloque.
			w.printf("  update block set position = position + 1000 where session_id = s;\n")
			w.printf("  update block set position = position - 1000 + %d where session_id = s;\n", n)
			w.printf("  update workout_amrap a set block_position = block_position + 1000\n")
			w.printf("    from workout wo where wo.id = a.workout_id and wo.session_id = s;\n")
			w.printf("  update workout_amrap a set block_position = block_position - 1000 + %d\n", n)
			w.printf("    from workout wo where wo.id = a.workout_id and wo.session_id = s;\n")
			for i, b := range s.Warmup {
				w.phaseBlock(strconv.Itoa(i+1), b)
			}
		}
		if len(s.Mobility) > 0 {
			w.printf("  select max(position) into m from block where session_id = s;\n")
			for i, b := range s.Mobility {
				w.phaseBlock(fmt.Sprintf("m + %d", i+1), b)
			}
		}
	}
	w.printf("end\n$$;\n\ncommit;\n")
	return w.flush()
}

// phaseBlock inserta un bloque de la sesión s en la posición dada (una
// expresión SQL) y sus ítems.
func (s *sqlWriter) phaseBlock(position string, b PhaseBlock) {
	s.printf("  insert into block (session_id, position, type, phase)\n")
	s.printf("    values (s, %s, 'rounds', '%s') returning id into b;\n", position, b.Phase)
	s.printf("  insert into block_item (block_id, round, position, kind, exercise_id, side, duration_s, reps) values\n")
	optInt := func(v int) string {
		if v == 0 {
			return "null"
		}
		return strconv.Itoa(v)
	}
	for i, it := range b.Items {
		sep := ","
		if i == len(b.Items)-1 {
			sep = ";"
		}
		if it.Rest {
			s.printf("    (b, %d, %d, 'rest', null, null, %d, null)%s\n", it.Round, it.Position, it.DurationS, sep)
			continue
		}
		s.printf("    (b, %d, %d, 'exercise', (select id from exercise where slug = %s), %s, %s, %s)%s\n",
			it.Round, it.Position, str(it.ExerciseSlug), sideSQL(it.Side),
			optInt(it.DurationS), optInt(it.Reps), sep)
	}
}
