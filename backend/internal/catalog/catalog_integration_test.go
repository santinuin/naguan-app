package catalog

// Test de integración contra la base local con el seed cargado (ver
// internal/training/training_integration_test.go). Sin TEST_DATABASE_URL se
// saltea.

import (
	"context"
	"errors"
	"os"
	"slices"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/santinuin/naguan-app/backend/internal/db"
)

func setup(t *testing.T) (*Service, *pgxpool.Pool) {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL no está definida: se saltea el test de integración")
	}
	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	return NewService(db.New(pool)), pool
}

func TestGetExerciseIntegration(t *testing.T) {
	s, _ := setup(t)

	ex, err := s.GetExercise(context.Background(), "flexion")
	if err != nil {
		t.Fatal(err)
	}
	if ex.Name != "Flexión" || len(ex.Videos) == 0 || len(ex.Muscles) == 0 {
		t.Errorf("ejercicio incompleto: %+v", ex)
	}

	// El sentido de las progresiones (las columnas del índice de MH están
	// rotuladas al revés): la flexión con rodillas es más fácil que la
	// flexión, y la diamante más difícil.
	has := func(refs []ExerciseRef, slug string) bool {
		return slices.ContainsFunc(refs, func(r ExerciseRef) bool { return r.Slug == slug })
	}
	if !has(ex.Easier, "flexion-con-rodillas") {
		t.Errorf("Easier = %+v, want que incluya flexion-con-rodillas", ex.Easier)
	}
	if !has(ex.Harder, "flexion-diamante") {
		t.Errorf("Harder = %+v, want que incluya flexion-diamante", ex.Harder)
	}
}

func TestGetExerciseUnilateralHasVideoPerSide(t *testing.T) {
	s, pool := setup(t)
	// Cualquier ejercicio unilateral con videos por lado.
	var slug string
	err := pool.QueryRow(context.Background(),
		`select e.slug from exercise e join exercise_video v on v.exercise_id = e.id
		 where v.side = 'left' limit 1`).Scan(&slug)
	if err != nil {
		t.Fatal(err)
	}

	ex, err := s.GetExercise(context.Background(), slug)
	if err != nil {
		t.Fatal(err)
	}
	if len(ex.Videos) != 2 || *ex.Videos[0].Side != "left" || *ex.Videos[1].Side != "right" {
		t.Errorf("videos de %s = %+v, want izquierdo y derecho", slug, ex.Videos)
	}
}

func TestGetExerciseNotFoundIntegration(t *testing.T) {
	s, _ := setup(t)

	_, err := s.GetExercise(context.Background(), "no-existe")
	if !errors.Is(err, ErrNotFound) {
		t.Errorf("err = %v, want ErrNotFound", err)
	}
}
