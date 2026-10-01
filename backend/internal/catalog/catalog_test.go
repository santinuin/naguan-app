package catalog

import (
	"testing"

	"github.com/santinuin/naguan-app/backend/internal/db"
)

func ptr[T any](v T) *T { return &v }

func TestGroupBlocks(t *testing.T) {
	right := db.SideRight
	rows := []db.ListSessionItemsRow{
		{BlockPosition: 1, BlockType: db.BlockTypeTabata, Round: 1, Position: 1, Kind: db.ItemKindExercise,
			DurationS: ptr(int32(20)), ExerciseSlug: ptr("sentadilla"), ExerciseName: ptr("Sentadilla")},
		{BlockPosition: 1, BlockType: db.BlockTypeTabata, Round: 1, Position: 2, Kind: db.ItemKindRest,
			DurationS: ptr(int32(10))},
		{BlockPosition: 2, BlockType: db.BlockTypeAmrap, TimeCapS: ptr(int32(900)), Round: 1, Position: 1,
			Kind: db.ItemKindExercise, Reps: ptr(int16(10)), Side: &right,
			ExerciseSlug: ptr("zancada"), ExerciseName: ptr("Zancada")},
	}

	got := groupBlocks(rows)

	if len(got) != 2 {
		t.Fatalf("bloques = %d, want 2", len(got))
	}
	if got[0].Type != "tabata" || len(got[0].Items) != 2 {
		t.Errorf("bloque 1 = %s con %d ítems, want tabata con 2", got[0].Type, len(got[0].Items))
	}
	if rest := got[0].Items[1]; rest.Exercise != nil || rest.Kind != "rest" {
		t.Errorf("el descanso no debería tener ejercicio: %+v", rest)
	}
	amrap := got[1]
	if amrap.TimeCapS == nil || *amrap.TimeCapS != 900 {
		t.Errorf("tope del amrap = %v, want 900", amrap.TimeCapS)
	}
	if it := amrap.Items[0]; it.Side == nil || *it.Side != "right" || it.Exercise.Name != "Zancada" {
		t.Errorf("ítem del amrap = %+v", it)
	}
}

func TestGroupBlocksEmpty(t *testing.T) {
	// Una sesión sin ítems serializa "blocks": [] y no "blocks": null.
	if got := groupBlocks(nil); got == nil || len(got) != 0 {
		t.Errorf("groupBlocks(nil) = %#v, want slice vacío", got)
	}
}
