package training

import (
	"errors"
	"testing"
	"time"
)

func ptr[T any](v T) *T { return &v }

// now es la "hora actual" fija de estos tests: el día siguiente a la
// Fragua de ejemplo.
var now = time.Date(2026, 10, 2, 12, 0, 0, 0, time.UTC)

func validWorkout() NewWorkout {
	finished := time.Date(2026, 10, 1, 21, 30, 0, 0, time.UTC)
	return NewWorkout{
		SessionID:  1,
		StartedAt:  finished.Add(-40 * time.Minute),
		FinishedAt: finished,
		LocalDate:  "2026-10-01",
		Items: []ItemResult{
			{BlockItemID: 10, Reps: ptr[int16](12)},
			{BlockItemID: 11, DurationS: ptr[int32](45)},
		},
	}
}

func TestValidate(t *testing.T) {
	tests := []struct {
		name   string
		modify func(w *NewWorkout)
		ok     bool
	}{
		{"válido", func(*NewWorkout) {}, true},
		{"sin ítems también vale", func(w *NewWorkout) { w.Items = nil }, true},
		// Córdoba es UTC-3: una Fragua a las 23:30 locales ya es el día
		// siguiente en UTC, y el día local sigue siendo válido.
		{"día local anterior al UTC", func(w *NewWorkout) {
			w.FinishedAt = time.Date(2026, 10, 2, 2, 30, 0, 0, time.UTC)
			w.StartedAt = w.FinishedAt.Add(-time.Hour)
		}, true},
		{"sin sesión", func(w *NewWorkout) { w.SessionID = 0 }, false},
		{"termina antes de empezar", func(w *NewWorkout) { w.StartedAt = w.FinishedAt.Add(time.Minute) }, false},
		{"dura demasiado", func(w *NewWorkout) { w.StartedAt = w.FinishedAt.Add(-13 * time.Hour) }, false},
		{"en el futuro", func(w *NewWorkout) {
			w.FinishedAt = now.Add(time.Hour)
			w.StartedAt = w.FinishedAt.Add(-time.Minute)
			w.LocalDate = w.FinishedAt.Format(time.DateOnly)
		}, false},
		{"fecha mal formada", func(w *NewWorkout) { w.LocalDate = "01/10/2026" }, false},
		{"día local muy lejano", func(w *NewWorkout) { w.LocalDate = "2026-09-25" }, false},
		{"ítem repetido", func(w *NewWorkout) { w.Items[1].BlockItemID = 10 }, false},
		{"ítem vacío", func(w *NewWorkout) { w.Items[0].Reps = nil }, false},
		{"reps negativas", func(w *NewWorkout) { w.Items[0].Reps = ptr[int16](-1) }, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			w := validWorkout()
			tt.modify(&w)

			_, err := w.validate(now)

			if tt.ok && err != nil {
				t.Errorf("err = %v, want nil", err)
			}
			// errors.As busca en la cadena un error del tipo pedido y, si
			// lo encuentra, lo asigna a la variable (como un catch por
			// tipo de excepción).
			var verr *ValidationError
			if !tt.ok && !errors.As(err, &verr) {
				t.Errorf("err = %v, want *ValidationError", err)
			}
		})
	}
}
