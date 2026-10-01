package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/santinuin/naguan-app/backend/internal/training"
)

// fakeTraining registra con qué usuario y datos lo llamaron, y devuelve err
// si está configurado.
type fakeTraining struct {
	err        error
	gotUserID  string
	gotSlug    string
	gotWorkout training.NewWorkout
	gotLimit   int32
	gotToday   time.Time
}

func (f *fakeTraining) ListProgress(_ context.Context, uid string) ([]training.ProgramProgress, error) {
	f.gotUserID = uid
	return []training.ProgramProgress{}, f.err
}

func (f *fakeTraining) Progress(_ context.Context, uid, slug string) (training.ProgramProgressDetail, error) {
	f.gotUserID, f.gotSlug = uid, slug
	return training.ProgramProgressDetail{
		ProgramProgress: training.ProgramProgress{Program: training.ProgramRef{Slug: slug}},
	}, f.err
}

func (f *fakeTraining) ResetProgress(_ context.Context, uid, slug string) error {
	f.gotUserID, f.gotSlug = uid, slug
	return f.err
}

func (f *fakeTraining) RecordWorkout(_ context.Context, uid string, w training.NewWorkout) (training.Workout, error) {
	f.gotUserID, f.gotWorkout = uid, w
	return training.Workout{ID: 7}, f.err
}

func (f *fakeTraining) ListWorkouts(_ context.Context, uid string, limit int32) ([]training.Workout, error) {
	f.gotUserID, f.gotLimit = uid, limit
	return []training.Workout{}, f.err
}

func (f *fakeTraining) Stats(_ context.Context, uid string, today time.Time) (training.Stats, error) {
	f.gotUserID, f.gotToday = uid, today
	return training.Stats{}, f.err
}

func (f *fakeTraining) Records(_ context.Context, uid string) ([]training.Record, error) {
	f.gotUserID = uid
	return []training.Record{}, f.err
}

// doTraining hace un request autenticado (usuario "u1") con cuerpo opcional.
func doTraining(t *testing.T, tr Training, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer token-valido")
	rec := httptest.NewRecorder()
	NewRouter(Deps{
		Catalog: &fakeCatalog{}, Training: tr, Verifier: fakeVerifier{}, RequestTimeout: time.Second,
	}).ServeHTTP(rec, req)
	return rec
}

func TestProgressEndpoints(t *testing.T) {
	tr := &fakeTraining{}

	if rec := doTraining(t, tr, http.MethodGet, "/v1/me/programs", ""); rec.Code != http.StatusOK {
		t.Errorf("GET lista: status %d", rec.Code)
	}

	rec := doTraining(t, tr, http.MethodGet, "/v1/me/programs/primal", "")
	if rec.Code != http.StatusOK || tr.gotSlug != "primal" {
		t.Errorf("GET detalle: status %d, slug %q", rec.Code, tr.gotSlug)
	}
	// El usuario sale del token, no del cuerpo ni de la URL.
	if tr.gotUserID != "u1" {
		t.Errorf("usuario = %q, want u1", tr.gotUserID)
	}

	if rec := doTraining(t, tr, http.MethodDelete, "/v1/me/programs/aurum/progress", ""); rec.Code != http.StatusNoContent {
		t.Errorf("DELETE progreso: status %d, want 204", rec.Code)
	}

	missing := &fakeTraining{err: training.ErrProgramNotFound}
	if rec := doTraining(t, missing, http.MethodGet, "/v1/me/programs/nada", ""); rec.Code != http.StatusNotFound {
		t.Errorf("senda inexistente: status %d, want 404", rec.Code)
	}
}

func TestRecordWorkoutEndpoint(t *testing.T) {
	body := `{
		"session_id": 3,
		"started_at": "2026-10-01T20:00:00Z",
		"finished_at": "2026-10-01T20:40:00Z",
		"local_date": "2026-10-01",
		"items": [{"block_item_id": 10, "reps": 12}]
	}`
	tr := &fakeTraining{}

	rec := doTraining(t, tr, http.MethodPost, "/v1/me/workouts", body)

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, want 201: %s", rec.Code, rec.Body)
	}
	w := tr.gotWorkout
	if w.SessionID != 3 || len(w.Items) != 1 || *w.Items[0].Reps != 12 ||
		!w.FinishedAt.Equal(time.Date(2026, 10, 1, 20, 40, 0, 0, time.UTC)) {
		t.Errorf("workout decodificado = %+v", w)
	}
}

func TestStatsEndpoint(t *testing.T) {
	tr := &fakeTraining{}
	today := time.Now().UTC().Format(time.DateOnly)

	rec := doTraining(t, tr, http.MethodGet, "/v1/me/stats?today="+today, "")

	if rec.Code != http.StatusOK || tr.gotToday.Format(time.DateOnly) != today {
		t.Errorf("status %d, today recibido %v", rec.Code, tr.gotToday)
	}
}

func TestBadRequests(t *testing.T) {
	tests := []struct {
		name, method, path, body string
		err                      error
		wantInBody               string
	}{
		{"JSON roto", http.MethodPost, "/v1/me/workouts", `{"session_id":`, nil, "JSON inválido"},
		{"campo desconocido", http.MethodPost, "/v1/me/workouts", `{"sesion_id": 3}`, nil, "unknown field"},
		{"dos objetos", http.MethodPost, "/v1/me/workouts", `{} {}`, nil, "único objeto"},
		{"limit fuera de rango", http.MethodGet, "/v1/me/workouts?limit=500", "", nil, "limit"},
		{"stats sin today", http.MethodGet, "/v1/me/stats", "", nil, "today"},
		{"stats con today lejano", http.MethodGet, "/v1/me/stats?today=2020-01-01", "", nil, "today"},
		{"validación del dominio", http.MethodPost, "/v1/me/workouts", `{}`,
			&training.ValidationError{Msg: "falta session_id"}, "falta session_id"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := doTraining(t, &fakeTraining{err: tt.err}, tt.method, tt.path, tt.body)

			if rec.Code != http.StatusBadRequest {
				t.Errorf("status = %d, want 400", rec.Code)
			}
			if !strings.Contains(rec.Body.String(), tt.wantInBody) {
				t.Errorf("body = %s, want que contenga %q", rec.Body, tt.wantInBody)
			}
		})
	}
}

func TestListWorkoutsLimit(t *testing.T) {
	tr := &fakeTraining{}

	doTraining(t, tr, http.MethodGet, "/v1/me/workouts", "")
	if tr.gotLimit != defaultWorkoutsLimit {
		t.Errorf("limit por defecto = %d", tr.gotLimit)
	}
	doTraining(t, tr, http.MethodGet, "/v1/me/workouts?limit=5", "")
	if tr.gotLimit != 5 {
		t.Errorf("limit = %d, want 5", tr.gotLimit)
	}
}
