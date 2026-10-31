package planimport

import (
	"bytes"
	"fmt"
	"io"
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
	plan, err := parsePlan(strings.NewReader(planFixture), nil)
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
		if _, err := parsePlan(strings.NewReader(text), nil); err == nil {
			t.Errorf("%s: quería un error", name)
		}
	}
}

func TestBuildUnknownExercise(t *testing.T) {
	plan, err := parsePlan(strings.NewReader("= 1 | X\nvueltas x1\nFlexión rara | 3r\nend"), nil)
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
		"values ('flexion-a-una-mano', 'Flexión a una mano', true, false,",
		"  ((select id from exercise where slug = 'flexion'), (select id from exercise where slug = 'flexion-a-una-mano'))\n  on conflict do nothing;",
		"raise exception 'prueba ya está cargado'",
		"insert into program (slug, name, description, position)\n    values ('prueba', 'Prueba', 'Programa de prueba.', null)",
		"insert into program_session (program_id, position, session_id) values (p, 3, s);",
		"values (s, 2, 'ladder', 'main', null, false, null) returning id into b;",
		"(b, 1, 1, 'exercise', (select id from exercise where slug = 'sentadilla-bulgara'), 'right', null, 1, null, false, false),",
		"(b, 5, 3, 'rest', null, null, 60, null, null, false, false);",
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
	plan, err := parsePlan(strings.NewReader(kettlebellFixture), nil)
	if err != nil {
		t.Fatalf("parsePlan: %v", err)
	}
	extras, err := parseCatalogExtras(strings.NewReader("+ Swing a una mano | 9 | unilateral | carga\nUna mano.\n"))
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
	if !prog.Unilateral["swing-a-una-mano"] || !prog.Loaded["swing-a-una-mano"] {
		t.Errorf("unilateral y con carga: %v, %v", prog.Unilateral, prog.Loaded)
	}
	if want := [][2]string{{"swing-a-una-mano", "https://youtu.be/x"}}; !slices.Equal(prog.Videos, want) {
		t.Errorf("videos = %v", prog.Videos)
	}

	var buf bytes.Buffer
	if err := RenderSQL(&buf, prog); err != nil {
		t.Fatal(err)
	}
	for _, s := range []string{
		"values (s, 1, 'amrap', 'main', 300, false, null) returning id into b;",
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
		plan, err := parsePlan(strings.NewReader(text), nil)
		if err != nil {
			t.Fatalf("%s: parsePlan: %v", name, err)
		}
		if _, err := Build("x", "X", plan, &CatalogExtras{}, testCatalog()); err == nil {
			t.Errorf("%s: quería un error", name)
		}
	}
}

func TestIncludeUseApproachAndList(t *testing.T) {
	files := map[string]string{"comun.txt": "@HIIT\npirámide 3,2\nFlexión\nend\n"}
	open := func(name string) (io.ReadCloser, error) {
		text, ok := files[name]
		if !ok {
			return nil, fmt.Errorf("no existe %s", name)
		}
		return io.NopCloser(strings.NewReader(text)), nil
	}
	plan, err := parsePlan(strings.NewReader("incluir comun.txt\n= 1 | A\naproximación corta Sentadilla búlgara\nusar HIIT\n"), open)
	if err != nil {
		t.Fatalf("parsePlan: %v", err)
	}
	prog, err := Build("x", "X", plan, &CatalogExtras{}, testCatalog())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	blocks := prog.Sessions[0].Blocks
	if len(blocks) != 2 {
		t.Fatalf("bloques = %+v", blocks)
	}

	// Aproximación corta de un unilateral: 5, 3 y 2 por lado, con 30 s y
	// 60 s entre series y 120 s antes del trabajo.
	var got []string
	for _, it := range blocks[0].Items {
		if it.Rest {
			got = append(got, fmt.Sprintf("%ds", it.DurationS))
		} else {
			got = append(got, fmt.Sprintf("%d%s", it.Reps, it.Side))
		}
	}
	want := []string{"5right", "5left", "30s", "3right", "3left", "60s", "2right", "2left", "120s"}
	if !slices.Equal(got, want) {
		t.Errorf("aproximación = %v, quiero %v", got, want)
	}
	if !strings.HasPrefix(blocks[0].Note, "Aproximación corta") {
		t.Errorf("nota de la aproximación = %q", blocks[0].Note)
	}

	// La plantilla incluida, con su pirámide en lista.
	if b := blocks[1]; b.Type != "ladder" || len(b.Items) != 2 || b.Items[0].Reps != 3 || b.Items[1].Reps != 2 {
		t.Errorf("usar HIIT = %+v", b)
	}

	if _, err := parsePlan(strings.NewReader("= 1 | A\nusar NADA\n"), open); err == nil {
		t.Error("usar una plantilla que no existe: quería un error")
	}
	if _, err := parsePlan(strings.NewReader("incluir otro.txt\n"), open); err == nil {
		t.Error("incluir un archivo que no existe: quería un error")
	}
}

func TestBuildUsesOtherPlansExercises(t *testing.T) {
	plan, err := parsePlan(strings.NewReader("= 1 | X\nvueltas x1\nSwing | 10r\nend\n"), nil)
	if err != nil {
		t.Fatal(err)
	}
	other := &CatalogExtras{Exercises: []mhimport.NewExercise{{Slug: "swing", Name: "Swing"}}}
	prog, err := Build("x", "X", plan, &CatalogExtras{}, testCatalog(), other)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	// Se usa, pero no se inserta: lo inserta el seed del otro plan.
	if len(prog.NewExercises) != 0 || prog.Sessions[0].Blocks[0].Items[0].ExerciseSlug != "swing" {
		t.Errorf("programa = %+v", prog)
	}
}

func TestTimedPyramid(t *testing.T) {
	plan, err := parsePlan(strings.NewReader(`= 1 | P
pirámide 420s | después 60
Sentadilla búlgara | 1r
end
pirámide 300s
Flexión | 2r
Dominada | 2r
end
`), nil)
	if err != nil {
		t.Fatalf("parsePlan: %v", err)
	}
	prog, err := Build("x", "X", plan, &CatalogExtras{}, testCatalog())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	blocks := prog.Sessions[0].Blocks
	// La pirámide, el Enfriá en su propio bloque y la segunda pirámide.
	if len(blocks) != 3 {
		t.Fatalf("bloques = %+v", blocks)
	}
	wantFirst := []Item{
		{Round: 1, Position: 1, ExerciseSlug: "sentadilla-bulgara", Side: mhimport.SideRight, Reps: 1},
		{Round: 1, Position: 2, ExerciseSlug: "sentadilla-bulgara", Side: mhimport.SideLeft, Reps: 1},
	}
	if b := blocks[0]; b.Type != "pyramid" || b.TimeCapS != 420 || !slices.Equal(b.Items, wantFirst) {
		t.Errorf("pirámide = %+v", b)
	}
	if b := blocks[1]; len(b.Items) != 1 || !b.Items[0].Rest || b.Items[0].DurationS != 60 {
		t.Errorf("Enfriá después = %+v", b)
	}
	if b := blocks[2]; b.Type != "pyramid" || b.TimeCapS != 300 || len(b.Items) != 2 || b.Items[1].Reps != 2 {
		t.Errorf("pirámide de a 2 = %+v", b)
	}

	for name, text := range map[string]string{
		"sin incremento":    "= 1 | X\npirámide 420s\nFlexión\nend",
		"por tiempo":        "= 1 | X\npirámide 420s\nPlancha | 30s\nend",
		"entre en una sola": "= 1 | X\npirámide 420s | entre 30\nFlexión | 1r\nend",
	} {
		if _, err := parsePlan(strings.NewReader(text), nil); err == nil {
			t.Errorf("%s: quería un error", name)
		}
	}
}

func TestPlanDetails(t *testing.T) {
	plan, err := parsePlan(strings.NewReader(`= 1 | X
marca: tiempo
vueltas x2 | entre 60 | opcional
nota: 2 s de subida
nota: y 2 de bajada.
Flexión | 5-8r
Dominada | 8r | máx
Sprint | 60s | cuenta
end
`), nil)
	if err != nil {
		t.Fatalf("parsePlan: %v", err)
	}
	prog, err := Build("x", "X", plan, &CatalogExtras{}, testCatalog())
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	s := prog.Sessions[0]
	b := s.Blocks[0]
	if !s.TimeRecord || !b.Optional || b.Note != "2 s de subida y 2 de bajada." {
		t.Errorf("sesión %v, bloque opcional %v, nota %q", s.TimeRecord, b.Optional, b.Note)
	}
	want := []Item{
		{Round: 1, Position: 1, ExerciseSlug: "flexion", Reps: 8, RepsMin: 5},
		{Round: 1, Position: 2, ExerciseSlug: "dominada", Reps: 8, Open: true},
		{Round: 1, Position: 3, ExerciseSlug: "sprint", DurationS: 60, CountReps: true},
	}
	if !slices.Equal(b.Items[:3], want) {
		t.Errorf("ítems = %+v", b.Items[:3])
	}

	var buf bytes.Buffer
	if err := RenderSQL(&buf, prog); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"insert into session (title, description, time_record) values ('X', null, true)",
		"values (s, 1, 'rounds_with_rest', 'main', null, true, '2 s de subida y 2 de bajada.')",
		"(select id from exercise where slug = 'flexion'), null, null, 8, 5, false, false)",
	} {
		if !strings.Contains(buf.String(), want) {
			t.Errorf("falta en el SQL: %s", want)
		}
	}

	for name, text := range map[string]string{
		"rango al revés":    "= 1 | X\nvueltas x1\nFlexión | 8-5r\nend",
		"rango en segundos": "= 1 | X\nvueltas x1\nPlancha | 30-60s\nend",
		"cuenta sin tiempo": "= 1 | X\nvueltas x1\nFlexión | 8r | cuenta\nend",
		"rango y máx":       "= 1 | X\nvueltas x1\nFlexión | 5-8r | máx\nend",
		"nota tarde":        "= 1 | X\nvueltas x1\nFlexión | 8r\nnota: tarde\nend",
		"marca con bloques": "= 1 | X\nvueltas x1\nFlexión | 8r\nend\nmarca: tiempo",
	} {
		if _, err := parsePlan(strings.NewReader(text), nil); err == nil {
			t.Errorf("%s: quería un error", name)
		}
	}
}

func TestRenderUpdateSQL(t *testing.T) {
	plan, err := parsePlan(strings.NewReader(`= 1 | X
marca: tiempo
vueltas x1 | opcional
nota: lento.
Flexión | 5-8r
Dominada | 8r
end
`), nil)
	if err != nil {
		t.Fatal(err)
	}
	prog, err := Build("x", "X", plan, &CatalogExtras{}, testCatalog())
	if err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := RenderUpdateSQL(&buf, prog); err != nil {
		t.Fatal(err)
	}
	sql := buf.String()
	for _, want := range []string{
		"where p.slug = 'x' and ps.position = 1;",
		"if n <> 1 then raise exception 'sesión 1: la base tiene % bloques y la transcripción 1', n; end if;",
		"update session set time_record = true where id = s;",
		"if n <> 2 then raise exception",
		"update block set optional = true, note = 'lento.' where id = b;",
		"update block_item set reps_min = 5, open = false, count_reps = false\n    where block_id = b and round = 1 and position = 1;",
	} {
		if !strings.Contains(sql, want) {
			t.Errorf("falta en el SQL: %s", want)
		}
	}
	// Solo actualiza lo que tiene algo distinto del valor por defecto: la
	// dominada no aparece.
	if strings.Contains(sql, "position = 2;") {
		t.Errorf("actualiza un ítem sin detalles:\n%s", sql)
	}
	// No inserta ni borra nada.
	if strings.Contains(sql, "insert") || strings.Contains(sql, "delete") {
		t.Errorf("el SQL de actualización inserta o borra:\n%s", sql)
	}
}

func TestCountRepsInTabata(t *testing.T) {
	plan, err := parsePlan(strings.NewReader("= 1 | X\ntabata x2 30/30\nBurpee | cuenta\nend\n"), nil)
	if err != nil {
		t.Fatal(err)
	}
	prog, err := Build("x", "X", plan, &CatalogExtras{}, &mhimport.Catalog{Exercises: []*mhimport.Exercise{{Slug: "burpee"}}})
	if err != nil {
		t.Fatal(err)
	}
	if it := prog.Sessions[0].Blocks[0].Items[0]; !it.CountReps || it.DurationS != 30 {
		t.Errorf("burpee del tabata = %+v", it)
	}
	// Fuera de un tabata, «cuenta» necesita su tiempo.
	if _, err := parsePlan(strings.NewReader("= 1 | X\nvueltas x1\nFlexión | cuenta\nend\n"), nil); err == nil {
		t.Error("cuenta sin medida fuera de un tabata: quería un error")
	}
}
