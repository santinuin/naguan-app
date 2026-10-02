package mhimport

import (
	"cmp"
	"encoding/json"
	"errors"
	"fmt"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/xuri/excelize/v2"
)

// SourceExercise es una fila del índice de ejercicios, tal como viene.
type SourceExercise struct {
	ID          int
	Coach       int
	Name        string
	Description string
	Video       string
	EasierID    int // 0 si no tiene
	HarderID    int
	MET         float64
	Muscles     []string
	Joints      []string
}

// SourceSession es una hoja "Sesion N" de un programa.
type SourceSession struct {
	Sheet  string
	Number int
	Rows   []SourceRow
	// Notes son los textos sueltos a la derecha de la tabla (título,
	// descripción, categoría), en orden de lectura.
	Notes []string
}

// SourceRow es una fila de la tabla de una sesión: un ejercicio (o un
// descanso) en una vuelta de un bloque.
type SourceRow struct {
	Line      int // número de fila en la hoja, para los mensajes de error
	Block     int
	BlockType string
	Set       int
	ExID      int
	ExTime    int
	Reps      int
	SetTime   int
	BlockTime int
}

// ReadIndex lee el índice de ejercicios: la primera hoja (los datos) y
// LookupList (el coach de cada ejercicio).
func ReadIndex(path string) ([]SourceExercise, error) {
	f, err := excelize.OpenFile(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	coaches, err := readCoaches(f)
	if err != nil {
		return nil, err
	}

	rows, err := f.GetRows(f.GetSheetList()[0])
	if err != nil {
		return nil, err
	}
	col, err := headerIndex(rows[0], "ID", "Nombre", "Descripción", "Video",
		"Más Fácil", "Más Difícil", "MET", "Músculos Implicados", "Articulaciones")
	if err != nil {
		return nil, fmt.Errorf("índice: %w", err)
	}

	var out []SourceExercise
	var errs []error
	for i, r := range rows[1:] {
		line := i + 2
		get := func(name string) string { return cell(r, col[name]) }
		if get("ID") == "" {
			continue
		}
		e := SourceExercise{
			Name:        get("Nombre"),
			Description: strings.TrimSpace(get("Descripción")),
			Video:       get("Video"),
		}
		var err error
		if e.ID, err = parseInt(get("ID")); err != nil {
			errs = append(errs, fmt.Errorf("índice fila %d: ID: %w", line, err))
			continue
		}
		e.Coach = coaches[e.ID]
		if e.MET, err = strconv.ParseFloat(get("MET"), 64); err != nil {
			errs = append(errs, fmt.Errorf("índice fila %d: MET: %w", line, err))
		}
		// Las columnas del índice están rotuladas AL REVÉS: "Más Fácil" trae
		// el ejercicio más difícil y viceversa (Flexión → "Más Fácil": Flexión
		// diamante, "Más Difícil": Flexión con rodillas). Pasa en todo el
		// índice, así que se leen cruzadas.
		if e.HarderID, err = parseRef(get("Más Fácil")); err != nil {
			errs = append(errs, fmt.Errorf("índice fila %d: Más Fácil: %w", line, err))
		}
		if e.EasierID, err = parseRef(get("Más Difícil")); err != nil {
			errs = append(errs, fmt.Errorf("índice fila %d: Más Difícil: %w", line, err))
		}
		if e.Muscles, err = parseList(get("Músculos Implicados")); err != nil {
			errs = append(errs, fmt.Errorf("índice fila %d: músculos: %w", line, err))
		}
		if e.Joints, err = parseList(get("Articulaciones")); err != nil {
			errs = append(errs, fmt.Errorf("índice fila %d: articulaciones: %w", line, err))
		}
		out = append(out, e)
	}
	return out, errors.Join(errs...)
}

func readCoaches(f *excelize.File) (map[int]int, error) {
	rows, err := f.GetRows("LookupList")
	if err != nil {
		return nil, err
	}
	coaches := make(map[int]int, len(rows))
	for _, r := range rows[1:] {
		id, err1 := parseInt(cell(r, 0))
		coach, err2 := parseInt(cell(r, 1))
		if err1 == nil && err2 == nil && id != 0 {
			coaches[id] = coach
		}
	}
	return coaches, nil
}

// sessionSheet reconoce "Sesion 12", "Sesión 30", "Sesion 5 ".
var sessionSheet = regexp.MustCompile(`(?i)^\s*sesi[oó]n\s+(\d+)\s*$`)

// headerAliases normaliza las 8 variantes de encabezado de las hojas de
// sesión a un nombre canónico.
var headerAliases = map[string]string{
	"block": "block", "bloque": "block",
	"block_type": "block_type", "bloque_type": "block_type", "set_block": "block_type",
	"set": "set", "set_time": "set_time", "block_time": "block_time",
	"ejercicio": "exercise", "ex_id": "ex_id", "ex_order": "ex_order",
	"tiempo ej.": "ex_time", "reps": "reps",
	"vídeo": "video", "vídeos": "video", "video": "video",
}

// cellKey identifica una celda de una hoja de sesión.
type cellKey struct {
	file, sheet string
	line        int
	col         string // nombre canónico del encabezado
}

// cellFixes corrige errores puntuales de la fuente. Cada corrección queda
// explícita y comentada, en vez de hacer el parseo tolerante (que podría
// esconder otros errores).
var cellFixes = func() map[cellKey]string {
	m := map[cellKey]string{
		// Ejercicio por tiempo (60 s); la celda de reps dice "Vídeo", corrida.
		{"Unbreakable.xlsx", "Sesion 1", 36, "reps"}: "0",
		// Filas sin bloque ni vuelta, entre filas del bloque 3.
		{"Unbreakable.xlsx", "Sesion 49", 15, "block"}: "3",
		{"Unbreakable.xlsx", "Sesion 49", 15, "set"}:   "1",
		{"Unbreakable.xlsx", "Sesion 49", 18, "block"}: "3",
		{"Unbreakable.xlsx", "Sesion 49", 18, "set"}:   "2",
	}
	// Las vueltas 2 a 5 del bloque 2 dicen bloque 3 (la vuelta 1 está en
	// el bloque 2 y el bloque 3 no tiene tipo).
	for line := 7; line <= 13; line++ {
		m[cellKey{"Unbreakable.xlsx", "Sesion 38", line, "block"}] = "2"
	}
	return m
}()

// noteLabels son textos de la zona de notas que no aportan contenido.
var noteLabels = map[string]bool{"listo": true, "descripción": true, "descripcion": true}

// ReadProgram lee todas las hojas "Sesion N" de un programa.
func ReadProgram(path string) ([]SourceSession, error) {
	f, err := excelize.OpenFile(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var out []SourceSession
	var errs []error
	for _, sheet := range f.GetSheetList() {
		m := sessionSheet.FindStringSubmatch(sheet)
		if m == nil {
			continue // "Presentación" y similares
		}
		n, _ := strconv.Atoi(m[1])
		rows, err := f.GetRows(sheet)
		if err != nil {
			return nil, err
		}
		fix := func(line int, col string) (string, bool) {
			v, ok := cellFixes[cellKey{filepath.Base(path), strings.TrimSpace(sheet), line, col}]
			return v, ok
		}
		s, err := parseSessionSheet(rows, fix)
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", sheet, err))
			continue
		}
		s.Sheet, s.Number = strings.TrimSpace(sheet), n
		out = append(out, s)
	}
	// La posición de la sesión en el programa sale del número de la hoja:
	// ordenamos y exigimos que sean 1, 2, 3... sin huecos.
	slices.SortFunc(out, func(a, b SourceSession) int { return cmp.Compare(a.Number, b.Number) })
	for i, s := range out {
		if s.Number != i+1 {
			errs = append(errs, fmt.Errorf("%s: se esperaba la sesión %d", s.Sheet, i+1))
			break
		}
	}
	return out, errors.Join(errs...)
}

func parseSessionSheet(rows [][]string, fix func(line int, col string) (string, bool)) (SourceSession, error) {
	var s SourceSession
	if len(rows) == 0 {
		return s, fmt.Errorf("hoja vacía")
	}

	// Mapeamos los encabezados conocidos a su columna. Un encabezado
	// desconocido (p. ej. "Fundamentos" en Ring Master) es una nota.
	col := map[string]int{}
	lastCol := -1
	for i, h := range rows[0] {
		if name, ok := headerAliases[strings.ToLower(strings.TrimSpace(h))]; ok {
			col[name] = i
			lastCol = max(lastCol, i)
		}
	}
	// ex_order se ignora: tiene errores de tipeo y el orden de las filas
	// siempre es el de ejecución.
	for _, need := range []string{"block", "set", "ex_id", "ex_time", "reps"} {
		if _, ok := col[need]; !ok {
			return s, fmt.Errorf("falta la columna %q", need)
		}
	}

	var errs []error
	for i, r := range rows {
		line := i + 1
		// Todo lo que está a la derecha de la tabla son notas.
		for c := lastCol + 1; c < len(r); c++ {
			if t := strings.TrimSpace(r[c]); isNote(t) {
				s.Notes = append(s.Notes, t)
			}
		}
		if i == 0 || cell(r, col["ex_id"]) == "" {
			continue
		}

		row := SourceRow{Line: line, BlockType: cell(r, colOr(col, "block_type"))}
		ints := []struct {
			name string
			dst  *int
		}{
			{"block", &row.Block}, {"set", &row.Set}, {"ex_id", &row.ExID},
			{"ex_time", &row.ExTime}, {"reps", &row.Reps},
			{"set_time", &row.SetTime}, {"block_time", &row.BlockTime},
		}
		for _, f := range ints {
			raw := cell(r, colOr(col, f.name))
			if fixed, ok := fix(line, f.name); ok {
				raw = fixed
			}
			v, err := parseInt(raw)
			if err != nil {
				errs = append(errs, fmt.Errorf("fila %d, %s: %w", line, f.name, err))
			}
			*f.dst = v
		}
		s.Rows = append(s.Rows, row)
	}
	return s, errors.Join(errs...)
}

func isNote(t string) bool {
	return t != "" && !noteLabels[strings.ToLower(t)] &&
		!strings.HasPrefix(t, "http://") && !strings.HasPrefix(t, "https://")
}

// colOr devuelve la columna de un encabezado opcional, o -1 si la hoja no
// lo tiene (y entonces cell devuelve "").
func colOr(col map[string]int, name string) int {
	if c, ok := col[name]; ok {
		return c
	}
	return -1
}

func cell(r []string, i int) string {
	if i < 0 || i >= len(r) {
		return ""
	}
	return strings.TrimSpace(r[i])
}

func headerIndex(header []string, names ...string) (map[string]int, error) {
	col := map[string]int{}
	for i, h := range header {
		col[strings.TrimSpace(h)] = i
	}
	for _, n := range names {
		if _, ok := col[n]; !ok {
			return nil, fmt.Errorf("falta la columna %q", n)
		}
	}
	return col, nil
}

// parseInt acepta "", "45", "45.0" y " 10 ": las celdas vienen como número
// o como texto según quién haya editado la planilla. Vacío es 0.
func parseInt(s string) (int, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, nil
	}
	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0, fmt.Errorf("%q no es un número", s)
	}
	if f != float64(int(f)) {
		return 0, fmt.Errorf("%q no es un entero", s)
	}
	return int(f), nil
}

// parseRef lee una referencia del tipo "5218 - Plancha equilibrio".
func parseRef(s string) (int, error) {
	if s == "" {
		return 0, nil
	}
	id, _, ok := strings.Cut(s, " - ")
	if !ok {
		return 0, fmt.Errorf("formato inesperado %q", s)
	}
	return parseInt(id)
}

// parseList lee las listas JSON del índice: ["cadera", " hombros"]. Descarta
// los valores basura ("", "0").
func parseList(s string) ([]string, error) {
	if s == "" {
		return nil, nil
	}
	var raw []string
	if err := json.Unmarshal([]byte(s), &raw); err != nil {
		return nil, fmt.Errorf("lista inválida %q: %w", s, err)
	}
	var out []string
	for _, v := range raw {
		if v = strings.TrimSpace(v); v != "" && v != "0" {
			out = append(out, v)
		}
	}
	return out, nil
}
