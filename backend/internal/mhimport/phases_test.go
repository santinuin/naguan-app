package mhimport

import (
	"slices"
	"strings"
	"testing"
)

const phasePlanFixture = `
# comentario
@CAL
Saltar a la cuerda | 60s
Giros articulares | 1r
Arch hold | 10s | x2
x2:
Flexión escapular | 10r
Plancha lateral | 30s
end

@MOV
Colgarse | 20s

1: CAL MOV
2: CAL MOV
`

func TestBuildPhases(t *testing.T) {
	plan, err := parsePhasePlan(strings.NewReader(phasePlanFixture))
	if err != nil {
		t.Fatalf("parsePhasePlan: %v", err)
	}
	// Los dos primeros ejercicios (una vuelta) van juntos; el x2 suelto y el
	// grupo x2, aparte.
	if g := plan.Templates["CAL"]; len(g) != 3 || g[0].Rounds != 1 || len(g[0].Items) != 2 ||
		g[1].Rounds != 2 || g[2].Rounds != 2 || len(g[2].Items) != 2 {
		t.Fatalf("grupos de CAL = %+v", g)
	}

	cat := &Catalog{Exercises: []*Exercise{
		{Slug: "saltar-a-la-cuerda"}, {Slug: "giros-articulares"},
		{Slug: "superman"}, // Arch hold, por alias
		{Slug: "flexion-escapular"}, {Slug: "plancha-lateral", Unilateral: true},
	}}
	sessions, err := BuildPhases(plan, cat)
	if err != nil {
		t.Fatalf("BuildPhases: %v", err)
	}
	if len(sessions) != 2 || sessions[0].Position != 1 || sessions[1].Position != 2 {
		t.Fatalf("sesiones = %+v", sessions)
	}
	w := sessions[0].Warmup
	if len(w) != 3 || w[0].Phase != PhaseWarmup {
		t.Fatalf("calentamiento = %+v", w)
	}
	// Un solo ejercicio x2: entre las dos vueltas, un Enfriá.
	wantArch := []PhaseBlockItem{
		{Round: 1, Position: 1, ExerciseSlug: "superman", DurationS: 10},
		{Round: 1, Position: 2, DurationS: PhaseRestS, Rest: true},
		{Round: 2, Position: 1, ExerciseSlug: "superman", DurationS: 10},
	}
	if got := w[1].Items; !slices.Equal(got, wantArch) {
		t.Errorf("Arch hold x2 = %+v, want %+v", got, wantArch)
	}
	// Grupo x2 con un unilateral: por vuelta, flexión, derecha, izquierda. Son
	// dos ejercicios: sin Enfriá entre vueltas.
	want := []PhaseBlockItem{
		{1, 1, "flexion-escapular", SideNone, 0, 10, false},
		{1, 2, "plancha-lateral", SideRight, 30, 0, false},
		{1, 3, "plancha-lateral", SideLeft, 30, 0, false},
		{2, 1, "flexion-escapular", SideNone, 0, 10, false},
		{2, 2, "plancha-lateral", SideRight, 30, 0, false},
		{2, 3, "plancha-lateral", SideLeft, 30, 0, false},
	}
	if got := w[2].Items; !slices.Equal(got, want) {
		t.Errorf("grupo = %+v, want %+v", got, want)
	}
	// En el SQL, el Enfriá va sin ejercicio ni lado.
	var sql strings.Builder
	if err := RenderPhasesSQL(&sql, "unbreakable", sessions); err != nil {
		t.Fatal(err)
	}
	if row := "(b, 1, 2, 'rest', null, null, 10, null),"; !strings.Contains(sql.String(), row) {
		t.Errorf("falta el Enfriá %q en el SQL:\n%s", row, sql.String())
	}
	// Colgarse no está en el catálogo: es uno de los ejercicios nuevos.
	if m := sessions[0].Mobility; len(m) != 1 || m[0].Items[0].ExerciseSlug != "colgarse" {
		t.Errorf("movilidad = %+v", m)
	}
}

func TestBuildPhasesErrors(t *testing.T) {
	if _, err := parsePhasePlan(strings.NewReader("@A\nx2:\nFlexión | 10r\n1: A B\n")); err == nil ||
		!strings.Contains(err.Error(), "end") || !strings.Contains(err.Error(), `"B"`) {
		t.Errorf("grupo sin end y plantilla inexistente: err = %v", err)
	}
	plan, err := parsePhasePlan(strings.NewReader("@A\nEjercicio inventado | 10r\n1: A A\n"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := BuildPhases(plan, &Catalog{}); err == nil || !strings.Contains(err.Error(), "inventado") {
		t.Errorf("ejercicio inexistente: err = %v", err)
	}
}
