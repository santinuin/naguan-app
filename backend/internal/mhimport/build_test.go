package mhimport

import (
	"strings"
	"testing"
)

// catalogFixture es un catálogo mínimo: el ID viejo 100 es "Flexión" y el
// 200 es "Plancha lateral" del lado derecho.
func catalogFixture() *Catalog {
	return &Catalog{BySource: map[int]ExerciseRef{
		100: {ExerciseID: 1},
		200: {ExerciseID: 2, Side: SideRight},
	}}
}

func TestBuildSession(t *testing.T) {
	src := SourceSession{
		Number: 3,
		Notes:  []string{"Tábata", "Completá 8 vueltas.\nSin pausas."},
		Rows: []SourceRow{
			{Line: 2, Block: 1, BlockType: "tabata", Set: 1, ExID: 100, ExTime: 20},
			{Line: 3, Block: 1, Set: 1, ExID: RestSourceID, ExTime: 10},
			{Line: 4, Block: 1, Set: 2, ExID: 200, Reps: 8},
			// Bloque sin tipo, solo descanso: se pega al bloque anterior.
			{Line: 5, Block: 2, Set: 1, ExID: RestSourceID, ExTime: 60},
			// Bloque con tope de tiempo: amrap.
			{Line: 6, Block: 3, BlockType: "interval_repetitions", Set: 1, SetTime: 900, ExID: 100, Reps: 10},
		},
	}

	s, err := BuildSession(src, catalogFixture())
	if err != nil {
		t.Fatalf("BuildSession: %v", err)
	}
	if s.Title != "Tábata" || s.Description != "Completá 8 vueltas.\nSin pausas." {
		t.Errorf("título/descripción = %q / %q", s.Title, s.Description)
	}
	if len(s.Blocks) != 2 {
		t.Fatalf("bloques = %d, want 2", len(s.Blocks))
	}

	tabata := s.Blocks[0]
	if tabata.Type != "tabata" || len(tabata.Items) != 4 {
		t.Fatalf("primer bloque = %s con %d ítems, want tabata con 4", tabata.Type, len(tabata.Items))
	}
	last := tabata.Items[3]
	if !last.Rest || last.Round != 2 || last.Position != 2 || last.DurationS != 60 {
		t.Errorf("descanso pegado = %+v, want descanso de 60 s en vuelta 2, posición 2", last)
	}
	if side := tabata.Items[2].Exercise.Side; side != SideRight {
		t.Errorf("lado de la plancha = %q, want right", side)
	}

	amrap := s.Blocks[1]
	if amrap.Type != "amrap" || amrap.TimeCapS != 900 {
		t.Errorf("segundo bloque = %s (%d s), want amrap (900 s)", amrap.Type, amrap.TimeCapS)
	}
}

func TestBuildSessionErrors(t *testing.T) {
	tests := []struct {
		name    string
		row     SourceRow
		wantErr string
	}{
		{"tiempo y reps", SourceRow{Block: 1, BlockType: "tabata", Set: 1, ExID: 100, ExTime: 20, Reps: 5}, "tiempo o reps"},
		{"ni tiempo ni reps", SourceRow{Block: 1, BlockType: "tabata", Set: 1, ExID: 100}, "tiempo o reps"},
		{"descanso sin duración", SourceRow{Block: 1, BlockType: "tabata", Set: 1, ExID: RestSourceID}, "sin duración"},
		{"ejercicio desconocido", SourceRow{Block: 1, BlockType: "tabata", Set: 1, ExID: 999, Reps: 5}, "no está en el catálogo"},
		{"tipo desconocido", SourceRow{Block: 1, BlockType: "zumba", Set: 1, ExID: 100, Reps: 5}, "desconocido"},
		{"bloque sin tipo", SourceRow{Block: 1, Set: 1, ExID: 100, Reps: 5}, "no tiene tipo"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := BuildSession(SourceSession{Rows: []SourceRow{tt.row}}, catalogFixture())
			if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
				t.Errorf("error = %v, want que contenga %q", err, tt.wantErr)
			}
		})
	}
}
