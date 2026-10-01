package mhimport

import (
	"cmp"
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"
	"unicode/utf8"
)

const (
	// RestSourceID es "Descanso" en el índice original. En el modelo nuevo
	// no es un ejercicio sino un ítem de descanso.
	RestSourceID = 5968
	// canonicalCoach es el coach de Unbreakable y Ring Master: ante un
	// ejercicio duplicado, gana su versión.
	canonicalCoach = 727
)

type Exercise struct {
	ID          int64
	Slug        string
	Name        string
	Unilateral  bool
	Description string
	MET         float64
	Videos      map[Side]string
	Muscles     []string // slugs
	Joints      []string // slugs
}

type Lookup struct {
	ID         int64
	Slug, Name string
}

type Progression struct{ EasierID, HarderID int64 }

// ExerciseRef es a qué ejercicio y lado apunta un ID del índice original.
type ExerciseRef struct {
	ExerciseID int64
	Side       Side
}

type Catalog struct {
	Exercises    []*Exercise
	Muscles      []Lookup
	Joints       []Lookup
	Progressions []Progression
	// BySource traduce los IDs viejos (los ex_id de los programas).
	BySource map[int]ExerciseRef
}

// BuildCatalog arma el catálogo nuevo: agrupa las filas del CSV por nombre,
// elige la versión canónica de cada ejercicio y lado, y traduce las
// progresiones. Devuelve advertencias (datos descartados) aparte de los
// errores (datos que impiden continuar).
func BuildCatalog(index []SourceExercise, names []NameRow) (*Catalog, []string, error) {
	byID := make(map[int]SourceExercise, len(index))
	for _, e := range index {
		byID[e.ID] = e
	}

	var errs []error
	groups := map[string][]NameRow{}
	named := map[int]bool{}
	for _, r := range names {
		if _, ok := byID[r.SourceID]; !ok {
			errs = append(errs, fmt.Errorf("CSV: el ID %d no está en el índice", r.SourceID))
			continue
		}
		if strings.TrimSpace(r.Name) == "" {
			errs = append(errs, fmt.Errorf("CSV: el ID %d no tiene nombre", r.SourceID))
			continue
		}
		named[r.SourceID] = true
		groups[r.Name] = append(groups[r.Name], r)
	}
	for _, e := range index {
		if e.ID != RestSourceID && !named[e.ID] {
			errs = append(errs, fmt.Errorf("CSV: falta el ID %d (%s); corré el comando names", e.ID, e.Name))
		}
	}
	if len(errs) > 0 {
		return nil, nil, errors.Join(errs...)
	}

	cat := &Catalog{BySource: map[int]ExerciseRef{}}
	muscles, joints := newLookupSet(), newLookupSet()
	slugs := map[string]string{}

	// Recorremos los nombres ordenados: los IDs nuevos son deterministas.
	for _, name := range slices.Sorted(maps.Keys(groups)) {
		rows := groups[name]
		ex := &Exercise{
			ID:     int64(len(cat.Exercises) + 1),
			Slug:   Slug(name),
			Name:   name,
			Videos: map[Side]string{},
		}
		if other, dup := slugs[ex.Slug]; dup {
			errs = append(errs, fmt.Errorf("%q y %q generan el mismo slug %q", name, other, ex.Slug))
			continue
		}
		slugs[ex.Slug] = name

		canon, err := canonicalBySide(rows)
		if err != nil {
			errs = append(errs, fmt.Errorf("%q: %w", name, err))
			continue
		}

		var primary SourceExercise
		for _, side := range []Side{SideNone, SideLeft, SideRight} {
			r, ok := canon[side]
			if !ok {
				continue
			}
			src := byID[r.SourceID]
			if primary.ID == 0 {
				primary = src
			}
			if side != SideNone {
				ex.Unilateral = true
			}
			if src.Video != "" {
				ex.Videos[side] = src.Video
			}
		}
		ex.MET = primary.MET
		ex.Description = primary.Description
		for _, r := range rows {
			src := byID[r.SourceID]
			if ex.Description == "" {
				ex.Description = src.Description
			}
			ex.Muscles = appendUnique(ex.Muscles, muscles.addAll(src.Muscles)...)
			ex.Joints = appendUnique(ex.Joints, joints.addAll(src.Joints)...)
			cat.BySource[r.SourceID] = ExerciseRef{ex.ID, r.Side}
		}
		cat.Exercises = append(cat.Exercises, ex)
	}
	if len(errs) > 0 {
		return nil, nil, errors.Join(errs...)
	}

	cat.Muscles, cat.Joints = muscles.list(), joints.list()
	var warns []string
	nameOf := func(id int64) string { return cat.Exercises[id-1].Name }
	cat.Progressions, warns = buildProgressions(index, cat.BySource, nameOf)
	return cat, warns, nil
}

// canonicalBySide elige, para cada lado, qué fila del índice representa al
// ejercicio: la del coach canónico, o la de ID más bajo. Dos filas del
// mismo coach y lado con el mismo nombre son un error: o son el mismo
// ejercicio repetido, o son distintos y hay que renombrar uno en el CSV.
func canonicalBySide(rows []NameRow) (map[Side]NameRow, error) {
	canon := map[Side]NameRow{}
	seen := map[[2]any]int{}
	for _, r := range rows {
		key := [2]any{r.Side, r.Coach}
		if prev, ok := seen[key]; ok {
			return nil, fmt.Errorf("los IDs %d y %d tienen el mismo coach y lado; renombrá uno en el CSV", prev, r.SourceID)
		}
		seen[key] = r.SourceID
		cur, ok := canon[r.Side]
		if !ok || better(r, cur) {
			canon[r.Side] = r
		}
	}
	return canon, nil
}

func better(a, b NameRow) bool {
	if (a.Coach == canonicalCoach) != (b.Coach == canonicalCoach) {
		return a.Coach == canonicalCoach
	}
	return a.SourceID < b.SourceID
}

// buildProgressions traduce las columnas "Más fácil"/"Más difícil" a aristas
// entre ejercicios nuevos. Al fusionar pueden aparecer lazos (A → A) o
// contradicciones (A → B y B → A): se descartan con una advertencia.
func buildProgressions(index []SourceExercise, ref map[int]ExerciseRef, nameOf func(int64) string) ([]Progression, []string) {
	var warns []string
	edges := map[Progression]bool{}
	add := func(easier, harder, from int) {
		e, ok1 := ref[easier]
		h, ok2 := ref[harder]
		switch {
		case !ok1 || !ok2:
			warns = append(warns, fmt.Sprintf("progresión %d → %d (desde %d): un extremo no es un ejercicio", easier, harder, from))
		case e.ExerciseID != h.ExerciseID:
			edges[Progression{e.ExerciseID, h.ExerciseID}] = true
		}
	}
	for _, e := range index {
		if e.EasierID != 0 {
			add(e.EasierID, e.ID, e.ID)
		}
		if e.HarderID != 0 {
			add(e.ID, e.HarderID, e.ID)
		}
	}

	var out []Progression
	for p := range edges {
		if edges[Progression{p.HarderID, p.EasierID}] {
			if p.EasierID < p.HarderID { // reportar una sola vez por par
				warns = append(warns, fmt.Sprintf("progresión contradictoria entre %q y %q: se descarta",
					nameOf(p.EasierID), nameOf(p.HarderID)))
			}
			continue
		}
		out = append(out, p)
	}
	slices.SortFunc(out, func(a, b Progression) int {
		return cmp.Or(cmp.Compare(a.EasierID, b.EasierID), cmp.Compare(a.HarderID, b.HarderID))
	})
	// Recorrer un map no tiene orden fijo: ordenamos para que la salida
	// sea la misma en cada corrida.
	slices.Sort(warns)
	return out, warns
}

// ── Sesiones ────────────────────────────────────────────────────────────────

type Program struct {
	ID       int64
	Slug     string
	Name     string
	Sessions []*Session // la posición en el programa es el índice + 1
}

type Session struct {
	ID          int64
	Title       string
	Description string
	Blocks      []*Block
}

type Block struct {
	Type     string
	TimeCapS int
	Items    []Item
}

type Item struct {
	Round, Position int
	Rest            bool
	Exercise        ExerciseRef
	DurationS       int
	Reps            int
}

// blockTypes traduce los tipos de MH a los nuestros. Un bloque con tope de
// tiempo pasa a ser amrap, sea cual sea su tipo original.
var blockTypes = map[string]string{
	"interval_repetitions":            "rounds",
	"interval_repetitions_with_pause": "rounds_with_rest",
	"tabata":                          "tabata",
	"super_series":                    "superset",
	"to_the_one":                      "ladder",
	"spartan_race":                    "ladder",
	"paleo_run":                       "rounds",
}

// BuildSession convierte una hoja de sesión en una sesión del modelo.
func BuildSession(src SourceSession, cat *Catalog) (*Session, error) {
	s := &Session{}
	s.Title, s.Description = titleAndDescription(src)

	// Agrupamos las filas por bloque, en el orden en que aparecen.
	var order []int
	rows := map[int][]SourceRow{}
	for _, r := range src.Rows {
		if _, ok := rows[r.Block]; !ok {
			order = append(order, r.Block)
		}
		rows[r.Block] = append(rows[r.Block], r)
	}

	var errs []error
	for _, n := range order {
		b, err := buildBlock(rows[n], cat)
		if err != nil {
			errs = append(errs, fmt.Errorf("bloque %d: %w", n, err))
			continue
		}
		if b.Type != "" {
			s.Blocks = append(s.Blocks, b)
			continue
		}
		// Un bloque sin tipo que solo tiene descansos es la pausa entre dos
		// bloques: se agrega al final del bloque anterior.
		if len(s.Blocks) == 0 || !allRest(b.Items) {
			errs = append(errs, fmt.Errorf("bloque %d: no tiene tipo", n))
			continue
		}
		prev := s.Blocks[len(s.Blocks)-1]
		last := prev.Items[len(prev.Items)-1]
		for i, it := range b.Items {
			it.Round, it.Position = last.Round, last.Position+i+1
			prev.Items = append(prev.Items, it)
		}
	}
	return s, errors.Join(errs...)
}

func buildBlock(rows []SourceRow, cat *Catalog) (*Block, error) {
	b := &Block{}
	var srcType string
	for _, r := range rows {
		if srcType == "" {
			srcType = r.BlockType
		}
		b.TimeCapS = max(b.TimeCapS, r.SetTime, r.BlockTime)
	}
	if srcType != "" {
		t, ok := blockTypes[srcType]
		if !ok {
			return nil, fmt.Errorf("tipo de bloque desconocido %q", srcType)
		}
		b.Type = t
	}
	if b.TimeCapS > 0 {
		b.Type = "amrap"
	}

	var errs []error
	// La posición es el orden de la fila dentro de su vuelta.
	nextPos := map[int]int{}
	for _, r := range rows {
		if r.Set <= 0 {
			errs = append(errs, fmt.Errorf("fila %d: vuelta inválida %d", r.Line, r.Set))
			continue
		}
		nextPos[r.Set]++
		it := Item{Round: r.Set, Position: nextPos[r.Set]}

		if r.ExID == RestSourceID {
			if r.ExTime <= 0 {
				errs = append(errs, fmt.Errorf("fila %d: descanso sin duración", r.Line))
				continue
			}
			it.Rest, it.DurationS = true, r.ExTime
		} else {
			ref, ok := cat.BySource[r.ExID]
			if !ok {
				errs = append(errs, fmt.Errorf("fila %d: ex_id %d no está en el catálogo", r.Line, r.ExID))
				continue
			}
			if (r.ExTime > 0) == (r.Reps > 0) {
				errs = append(errs, fmt.Errorf("fila %d: debe tener tiempo o reps, no ambos ni ninguno (%d s, %d reps)", r.Line, r.ExTime, r.Reps))
				continue
			}
			it.Exercise, it.DurationS, it.Reps = ref, r.ExTime, r.Reps
		}
		b.Items = append(b.Items, it)
	}
	if b.Type == "amrap" && slices.ContainsFunc(b.Items, func(it Item) bool { return it.Round != 1 }) {
		errs = append(errs, fmt.Errorf("amrap con más de una vuelta escrita"))
	}
	slices.SortFunc(b.Items, func(x, y Item) int {
		return cmp.Or(cmp.Compare(x.Round, y.Round), cmp.Compare(x.Position, y.Position))
	})
	return b, errors.Join(errs...)
}

func allRest(items []Item) bool {
	return !slices.ContainsFunc(items, func(it Item) bool { return !it.Rest })
}

// titleAndDescription usa la primera nota corta de una línea como título y el
// resto como descripción. Sin notas, el título es "Sesión N".
func titleAndDescription(src SourceSession) (string, string) {
	title := ""
	var desc []string
	for _, n := range src.Notes {
		if title == "" && !strings.Contains(n, "\n") && utf8.RuneCountInString(n) <= 80 {
			title = n
			continue
		}
		desc = append(desc, n)
	}
	if title == "" {
		title = fmt.Sprintf("Sesión %d", src.Number)
	}
	return title, strings.Join(desc, "\n\n")
}

// ── Utilidades ──────────────────────────────────────────────────────────────

// lookupSet acumula músculos o articulaciones normalizados, sin repetir.
type lookupSet struct {
	bySlug map[string]Lookup
}

func newLookupSet() *lookupSet { return &lookupSet{bySlug: map[string]Lookup{}} }

// lookupFixes corrige la ortografía de algunos valores del índice.
var lookupFixes = map[string]string{
	"adductores":     "aductores",
	"psoas - iliaco": "psoas ilíaco",
}

func (s *lookupSet) addAll(names []string) []string {
	var slugs []string
	for _, n := range names {
		n = strings.ToLower(strings.TrimSpace(n))
		if fix, ok := lookupFixes[n]; ok {
			n = fix
		}
		slug := Slug(n)
		if _, ok := s.bySlug[slug]; !ok {
			s.bySlug[slug] = Lookup{Slug: slug, Name: upperFirst(n)}
		}
		slugs = append(slugs, slug)
	}
	return slugs
}

func (s *lookupSet) list() []Lookup {
	out := make([]Lookup, 0, len(s.bySlug))
	for _, slug := range slices.Sorted(maps.Keys(s.bySlug)) {
		l := s.bySlug[slug]
		l.ID = int64(len(out) + 1)
		out = append(out, l)
	}
	return out
}

func appendUnique(dst []string, vals ...string) []string {
	for _, v := range vals {
		if !slices.Contains(dst, v) {
			dst = append(dst, v)
		}
	}
	return dst
}
