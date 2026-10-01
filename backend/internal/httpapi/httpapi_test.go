package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/santinuin/naguan-app/backend/internal/catalog"
)

// fakeCatalog cumple la interfaz Catalog sin base de datos. Cada test
// configura lo que devuelve; es el @MockBean de este proyecto, pero escrito
// a mano (sin Mockito: en Go se usan fakes simples como este).
type fakeCatalog struct {
	programs []catalog.ProgramSummary
	program  catalog.Program
	session  catalog.Session
	err      error
	gotSlug  string
	gotID    int64
}

func (f *fakeCatalog) ListPrograms(context.Context) ([]catalog.ProgramSummary, error) {
	return f.programs, f.err
}

func (f *fakeCatalog) GetProgram(_ context.Context, slug string) (catalog.Program, error) {
	f.gotSlug = slug
	return f.program, f.err
}

func (f *fakeCatalog) GetSession(_ context.Context, id int64) (catalog.Session, error) {
	f.gotID = id
	return f.session, f.err
}

// do ejecuta un request contra el router y devuelve la respuesta grabada.
func do(t *testing.T, cat Catalog, method, path string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, nil)
	rec := httptest.NewRecorder()
	NewRouter(cat).ServeHTTP(rec, req)
	return rec
}

func TestHealth(t *testing.T) {
	rec := do(t, &fakeCatalog{}, http.MethodGet, "/health")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusOK)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"status":"ok"}` {
		t.Errorf("body = %s", got)
	}
}

func TestHealthMethodNotAllowed(t *testing.T) {
	rec := do(t, &fakeCatalog{}, http.MethodPost, "/health")

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want %d", rec.Code, http.StatusMethodNotAllowed)
	}
}

func TestListPrograms(t *testing.T) {
	cat := &fakeCatalog{programs: []catalog.ProgramSummary{{Slug: "unbreakable", Name: "Unbreakable", SessionCount: 50}}}

	rec := do(t, cat, http.MethodGet, "/programs")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	want := `[{"slug":"unbreakable","name":"Unbreakable","description":null,"session_count":50}]`
	if got := strings.TrimSpace(rec.Body.String()); got != want {
		t.Errorf("body = %s\nwant  %s", got, want)
	}
}

func TestGetProgramPassesSlug(t *testing.T) {
	cat := &fakeCatalog{program: catalog.Program{Slug: "ring-master", Name: "Ring Master"}}

	rec := do(t, cat, http.MethodGet, "/programs/ring-master")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if cat.gotSlug != "ring-master" {
		t.Errorf("slug recibido = %q, want ring-master", cat.gotSlug)
	}
}

func TestGetSession(t *testing.T) {
	tests := []struct {
		name       string
		path       string
		err        error
		wantStatus int
		wantID     int64
	}{
		{"ok", "/sessions/7", nil, http.StatusOK, 7},
		{"no existe", "/sessions/999", catalog.ErrNotFound, http.StatusNotFound, 999},
		{"id no numérico", "/sessions/abc", nil, http.StatusBadRequest, 0},
		{"id negativo", "/sessions/-1", nil, http.StatusBadRequest, 0},
		{"error de la base", "/sessions/7", errors.New("se cayó la conexión"), http.StatusInternalServerError, 7},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cat := &fakeCatalog{err: tt.err}

			rec := do(t, cat, http.MethodGet, tt.path)

			if rec.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			if cat.gotID != tt.wantID {
				t.Errorf("id recibido = %d, want %d", cat.gotID, tt.wantID)
			}
			// El 500 no filtra el detalle del error al cliente.
			if strings.Contains(rec.Body.String(), "conexión") {
				t.Errorf("la respuesta expone el error interno: %s", rec.Body.String())
			}
		})
	}
}
