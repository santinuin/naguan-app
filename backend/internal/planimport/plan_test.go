package planimport

import (
	"bytes"
	"slices"
	"strings"
	"testing"

	"github.com/santinuin/naguan-app/backend/internal/mhimport"
)

const planFixture = `
> Programa de prueba.

@CAL
vueltas x1
Saltos de tijera | 25r
end

= 1 | Pirámide | CAL -
> Primera sesión.
pirámide 1-3-1 | después 60
Sentadilla búlgara
end
superset x2 | entre 30
Flexión | 10r
Dominada | 8r
end

= 2 | Tabata y HIIT
tabata x3 20/10 | después 60
Flexión
end
vueltas x2 | entre 60
Sprint | 20s
Enfriá | 20s
end

= 3 | copia de 1
`

const extrasFixture = `
# comentario
+ Flexión a una mano | 4 | unilateral
Apoyá una sola mano.
Bajá controlado.

progresión: Flexión > Flexión a una mano
`

func testCatalog() *mhimport.Catalog {
	return &mhimport.Catalog{Exercises: []*mhimport.Exercise{
		{Slug: "saltos-de-tijera"}, {Slug: "sentadilla-bulgara", Unilateral: true},
		{Slug: "flexion"}, {Slug: "dominada"}, {Slug: "sprint"},
	}}
}

func buildFixture(t *testing.T) *Program {
	t.Helper()
	plan, err := parsePlan(strings.NewReader(planFixture))
	if err != nil {
		t.Fatalf("parsePlan: %v", err)
	}
	extras, err := parseCatalogExtras(strings.NewReader(extrasFixture))
	if err != nil {
		t.Fatalf("parseCatalogExtras: %v", err)
	}
	prog, err := Build("prueba", "Prueba", plan, extras, testCatalog())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	return prog
}

func TestParseCatalogExtras(t *testing.T) {
	ex, err := parseCatalogExtras(strings.NewReader(extrasFixture))
	if err != nil {
		t.Fatal(err)
	}
	if len(ex.Exercises) != 1 || ex.Exercises[0].Slug != "flexion-a-una-mano" ||
		ex.Exercises[0].MET != 4 || ex.Exercises[0].Description != "Apoyá una sola mano.\nBajá controlado." {
		t.Errorf("ejercicios = %+v", ex.Exercises)
	}
	if !ex.Unilateral["flexion-a-una-mano"] {
		t.Error("tendría que ser unilateral")
	}
	if want := [][]string{{"Flexión", "Flexión a una mano"}}; !slices.EqualFunc(ex.Chains, want, slices.Equal) {
		t.Errorf("cadenas = %v", ex.Chains)
	}
}

func TestBuild(t *testing.T) {
	prog := buildFixture(t)
	if prog.Description != "Programa de prueba." || len(prog.Sessions) != 3 {
		t.Fatalf("programa = %+v", prog)
	}
	if want := [][2]string{{"flexion", "flexion-a-una-mano"}}; !slices.Equal(prog.Progressions, want) {
		t.Errorf("progresiones = %v", prog.Progressions)
	}

	s1 := prog.Sessions[0]
	if s1.Title != "Pirámide" || s1.Description != "Primera sesión." || len(s1.Blocks) != 3 {
		t.Fatalf("sesión 1 = %+v", s1)
	}
	if b := s1.Blocks[0]; b.Phase != mhimport.PhaseWarmup || b.Type != "rounds" || len(b.Items) != 1 {
		t.Errorf("calentamiento = %+v", b)
	}

	// Pirámide 1-3-1 de un unilateral: cada vuelta, derecha e izquierda con
	// las reps de la vuelta; el Enfriá de "después", al final de la última.
	ladder := s1.Blocks[1]
	if ladder.Type != "ladder" || ladder.Phase != phaseMain {
		t.Errorf("pirámide: tipo %q, fase %q", ladder.Type, ladder.Phase)
	}
	var reps []int
	for _, it := range ladder.Items {
		if !it.Rest {
			reps = append(reps, it.Reps)
		}
	}
	if want := []int{1, 1, 2, 2, 3, 3, 2, 2, 1, 1}; !slices.Equal(reps, want) {
		t.Errorf("reps de la pirámide = %v, quiero %v", reps, want)
	}
	if first := ladder.Items[0]; first.Side != mhimport.SideRight || first.ExerciseSlug != "sentadilla-bulgara" {
		t.Errorf("primer ítem = %+v", first)
	}
	if last := ladder.Items[len(ladder.Items)-1]; !last.Rest || last.DurationS != 60 || last.Round != 5 || last.Position != 3 {
		t.Errorf("último ítem = %+v", last)
	}

	// Superset x2 con Enfriá entre vueltas: no hay Enfriá al final.
	wantSuperset := []Item{
		{Round: 1, Position: 1, ExerciseSlug: "flexion", Reps: 10},
		{Round: 1, Position: 2, ExerciseSlug: "dominada", Reps: 8},
		{Round: 1, Position: 3, DurationS: 30, Rest: true},
		{Round: 2, Position: 1, ExerciseSlug: "flexion", Reps: 10},
		{Round: 2, Position: 2, ExerciseSlug: "dominada", Reps: 8},
	}
	if b := s1.Blocks[2]; b.Type != "superset" || !slices.Equal(b.Items, wantSuperset) {
		t.Errorf("superset = %+v", b)
	}

	// Tabata: trabajo y Enfriá en cada vuelta; en la última, el "después".
	wantTabata := []Item{
		{Round: 1, Position: 1, ExerciseSlug: "flexion", DurationS: 20},
		{Round: 1, Position: 2, DurationS: 10, Rest: true},
		{Round: 2, Position: 1, ExerciseSlug: "flexion", DurationS: 20},
		{Round: 2, Position: 2, DurationS: 10, Rest: true},
		{Round: 3, Position: 1, ExerciseSlug: "flexion", DurationS: 20},
		{Round: 3, Position: 2, DurationS: 60, Rest: true},
	}
	s2 := prog.Sessions[1]
	if b := s2.Blocks[0]; b.Type != "tabata" || !slices.Equal(b.Items, wantTabata) {
		t.Errorf("tabata = %+v", b)
	}
	// Un Enfriá dentro de la vuelta hace que el bloque sea con descansos.
	if b := s2.Blocks[1]; b.Type != "rounds_with_rest" || len(b.Items) != 5 {
		t.Errorf("HIIT = %+v", b)
	}

	// La copia repite todo.
	if s3 := prog.Sessions[2]; s3.Title != s1.Title || len(s3.Blocks) != len(s1.Blocks) {
		t.Errorf("copia = %+v", s3)
	}
}

func TestParseErrors(t *testing.T) {
	cases := map[string]string{
		"sin medida":            "= 1 | X\nvueltas x3\nFlexión\nend",
		"medida en pirámide":    "= 1 | X\npirámide 1-3-1\nFlexión | 3r\nend",
		"pico chico":            "= 1 | X\npirámide 3-2-1\nFlexión\nend",
		"sin end":               "= 1 | X\nvueltas x3\nFlexión | 3r",
		"fuera de orden":        "= 2 | X\nvueltas x1\nFlexión | 3r\nend",
		"plantilla inexistente": "= 1 | X | CAL\nvueltas x1\nFlexión | 3r\nend",
		"copia de sí misma":     "= 1 | copia de 1",
		"sin bloques":           "= 1 | X",
		"entre en una vuelta":   "= 1 | X\nvueltas x1 | entre 60\nFlexión | 3r\nend",
		"enfriá en reps":        "= 1 | X\nvueltas x2\nEnfriá | 3r\nend",
	}
	for name, text := range cases {
		if _, err := parsePlan(strings.NewReader(text)); err == nil {
			t.Errorf("%s: quería un error", name)
		}
	}
}

func TestBuildUnknownExercise(t *testing.T) {
	plan, err := parsePlan(strings.NewReader("= 1 | X\nvueltas x1\nFlexión rara | 3r\nend"))
	if err != nil {
		t.Fatal(err)
	}
	_, err = Build("x", "X", plan, &CatalogExtras{}, testCatalog())
	if err == nil || !strings.Contains(err.Error(), "Flexión rara") {
		t.Errorf("error = %v", err)
	}
}

func TestRenderSQL(t *testing.T) {
	var buf bytes.Buffer
	if err := RenderSQL(&buf, buildFixture(t)); err != nil {
		t.Fatal(err)
	}
	sql := buf.String()
	for _, want := range []string{
		"values ('flexion-a-una-mano', 'Flexión a una mano', true,",
		"  ((select id from exercise where slug = 'flexion'), (select id from exercise where slug = 'flexion-a-una-mano'))\n  on conflict do nothing;",
		"raise exception 'prueba ya está cargado'",
		"insert into program_session (program_id, position, session_id) values (p, 3, s);",
		"values (s, 2, 'ladder', 'main', null) returning id into b;",
		"(b, 1, 1, 'exercise', (select id from exercise where slug = 'sentadilla-bulgara'), 'right', null, 1),",
		"(b, 5, 3, 'rest', null, null, 60, null);",
	} {
		if !strings.Contains(sql, want) {
			t.Errorf("falta en el SQL: %s", want)
		}
	}
}

const kettlebellFixture = `
= 1 | Intervalos
amrap 300 | después 120
Swing a una mano | 5r
Sprint | 20s
end
tabata x4 20/10 alterna
Sprint
Swing a una mano | izq
end
vueltas x1
Swing a una mano | 300s | alternando
end

video: Swing a una mano | https://youtu.be/x
`

func TestBuildSidesAMRAPAndAlternation(t *testing.T) {
	plan, err := parsePlan(strings.NewReader(kettlebellFixture))
	if err != nil {
		t.Fatalf("parsePlan: %v", err)
	}
	extras, err := parseCatalogExtras(strings.NewReader("+ Swing a una mano | 9 | unilateral\nUna mano.\n"))
	if err != nil {
		t.Fatal(err)
	}
	prog, err := Build("kb", "KB", plan, extras, testCatalog())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	blocks := prog.Sessions[0].Blocks
	if len(blocks) != 4 {
		t.Fatalf("bloques = %+v", blocks)
	}

	// El AMRAP lleva el tope y una sola vuelta (el unilateral, por los dos
	// lados); el "después" va en un bloque aparte.
	if b := blocks[0]; b.Type != "amrap" || b.TimeCapS != 300 || len(b.Items) != 3 || b.Items[0].Side != mhimport.SideRight {
		t.Errorf("amrap = %+v", b)
	}
	wantRest := []Item{{Round: 1, Position: 1, DurationS: 120, Rest: true}}
	if b := blocks[1]; b.Type != "rounds" || !slices.Equal(b.Items, wantRest) {
		t.Errorf("Enfriá después del amrap = %+v", b)
	}

	// Tabata que alterna: un ejercicio por vuelta, con el lado que dice la
	// línea.
	wantTabata := []Item{
		{Round: 1, Position: 1, ExerciseSlug: "sprint", DurationS: 20},
		{Round: 1, Position: 2, DurationS: 10, Rest: true},
		{Round: 2, Position: 1, ExerciseSlug: "swing-a-una-mano", Side: mhimport.SideLeft, DurationS: 20},
		{Round: 2, Position: 2, DurationS: 10, Rest: true},
		{Round: 3, Position: 1, ExerciseSlug: "sprint", DurationS: 20},
		{Round: 3, Position: 2, DurationS: 10, Rest: true},
		{Round: 4, Position: 1, ExerciseSlug: "swing-a-una-mano", Side: mhimport.SideLeft, DurationS: 20},
	}
	if b := blocks[2]; !slices.Equal(b.Items, wantTabata) {
		t.Errorf("tabata alterna = %+v", b.Items)
	}

	// Alternando: un solo paso, sin lado.
	want := []Item{{Round: 1, Position: 1, ExerciseSlug: "swing-a-una-mano", DurationS: 300}}
	if b := blocks[3]; !slices.Equal(b.Items, want) {
		t.Errorf("alternando = %+v", b.Items)
	}
	if want := [][2]string{{"swing-a-una-mano", "https://youtu.be/x"}}; !slices.Equal(prog.Videos, want) {
		t.Errorf("videos = %v", prog.Videos)
	}

	var buf bytes.Buffer
	if err := RenderSQL(&buf, prog); err != nil {
		t.Fatal(err)
	}
	for _, s := range []string{
		"values (s, 1, 'amrap', 'main', 300) returning id into b;",
		"insert into exercise_video (exercise_id, side, url)\n  values ((select id from exercise where slug = 'swing-a-una-mano'), null, 'https://youtu.be/x')",
	} {
		if !strings.Contains(buf.String(), s) {
			t.Errorf("falta en el SQL: %s", s)
		}
	}
}

func TestBuildSideErrors(t *testing.T) {
	cases := map[string]string{
		"lado en bilateral":  "= 1 | X\nvueltas x1\nFlexión | 3r | der\nend",
		"video de existente": "= 1 | X\nvueltas x1\nFlexión | 3r\nend\nvideo: Flexión | https://youtu.be/x",
	}
	for name, text := range cases {
		plan, err := parsePlan(strings.NewReader(text))
		if err != nil {
			t.Fatalf("%s: parsePlan: %v", name, err)
		}
		if _, err := Build("x", "X", plan, &CatalogExtras{}, testCatalog()); err == nil {
			t.Errorf("%s: quería un error", name)
		}
	}
}
