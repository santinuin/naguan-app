package httpapi

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestChainOrder(t *testing.T) {
	// Cada middleware anota su nombre al entrar y al salir: el orden de las
	// anotaciones muestra cómo se anidan.
	var trace []string
	mark := func(name string) Middleware {
		return func(next http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				trace = append(trace, name+">")
				next.ServeHTTP(w, r)
				trace = append(trace, "<"+name)
			})
		}
	}
	final := http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		trace = append(trace, "handler")
	})

	chain(final, mark("a"), mark("b")).ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/", nil))

	want := "a> b> handler <b <a"
	if got := strings.Join(trace, " "); got != want {
		t.Errorf("orden = %q, want %q", got, want)
	}
}

func TestRecoverPanics(t *testing.T) {
	panicky := http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		var m map[string]int
		m["x"] = 1 // escribir en un map nil: panic
	})
	rec := httptest.NewRecorder()

	recoverPanics(panicky).ServeHTTP(rec, httptest.NewRequest("GET", "/", nil))

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", rec.Code)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"error":"error interno"}` {
		t.Errorf("body = %s", got)
	}
}

func TestStatusRecorder(t *testing.T) {
	tests := []struct {
		name       string
		handler    http.HandlerFunc
		wantStatus int
		wantBytes  int
	}{
		{"status explícito", func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusTeapot)
			w.Write([]byte("hola"))
		}, http.StatusTeapot, 4},
		{"Write sin WriteHeader es 200", func(w http.ResponseWriter, _ *http.Request) {
			w.Write([]byte("hola"))
		}, http.StatusOK, 4},
		{"sin escribir nada", func(http.ResponseWriter, *http.Request) {}, 0, 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := &statusRecorder{ResponseWriter: httptest.NewRecorder()}

			tt.handler(rec, httptest.NewRequest("GET", "/", nil))

			if rec.status != tt.wantStatus || rec.bytes != tt.wantBytes {
				t.Errorf("status, bytes = %d, %d; want %d, %d", rec.status, rec.bytes, tt.wantStatus, tt.wantBytes)
			}
		})
	}
}

func TestWithTimeoutSetsDeadline(t *testing.T) {
	var deadline time.Time
	var ok bool
	h := withTimeout(time.Minute)(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
		deadline, ok = r.Context().Deadline()
	}))

	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest("GET", "/", nil))

	if !ok || time.Until(deadline) > time.Minute {
		t.Errorf("deadline = %v (ok=%v), want a menos de un minuto", deadline, ok)
	}
}
