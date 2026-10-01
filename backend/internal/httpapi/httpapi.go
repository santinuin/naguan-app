// Package httpapi contiene el router HTTP y los handlers de la API.
package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/santinuin/naguan-app/backend/internal/catalog"
)

// Catalog es lo que los handlers necesitan del catálogo. La interfaz se
// define acá, del lado de quien la usa, y no en el paquete catalog: así los
// tests pasan un fake sin tocar la base, y *catalog.Service la cumple sin
// declararlo (en Go las interfaces se satisfacen implícitamente, no hay
// "implements").
type Catalog interface {
	ListPrograms(ctx context.Context) ([]catalog.ProgramSummary, error)
	GetProgram(ctx context.Context, slug string) (catalog.Program, error)
	GetSession(ctx context.Context, id int64) (catalog.Session, error)
}

// NewRouter arma el mux con todas las rutas y le aplica el middleware.
// Devuelve http.Handler (y no *http.ServeMux) para que main y los tests
// dependan solo de la interfaz.
func NewRouter(cat Catalog, requestTimeout time.Duration) http.Handler {
	mux := http.NewServeMux()

	// /health queda sin versión: lo consulta la infraestructura (Cloud Run,
	// un balanceador), no la app.
	mux.HandleFunc("GET /health", handleHealth)

	// Las rutas de la API van bajo /v1: cuando haya que romper el contrato,
	// conviven /v1 y /v2 mientras la app se actualiza. Desde Go 1.22 el mux
	// soporta método y wildcards en el patrón; no hace falta Chi ni Gin.
	h := catalogHandlers{cat: cat}
	mux.HandleFunc("GET /v1/programs", h.listPrograms)
	mux.HandleFunc("GET /v1/programs/{slug}", h.getProgram)
	mux.HandleFunc("GET /v1/sessions/{id}", h.getSession)

	// El orden importa: logRequests va afuera de todo para registrar
	// también los 500 que genera recoverPanics.
	return chain(mux,
		logRequests,
		recoverPanics,
		withTimeout(requestTimeout),
	)
}

type healthResponse struct {
	Status string `json:"status"`
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, healthResponse{Status: "ok"})
}

// catalogHandlers agrupa los handlers que comparten la dependencia: es lo
// más parecido a un @RestController con un campo inyectado.
type catalogHandlers struct {
	cat Catalog
}

func (h catalogHandlers) listPrograms(w http.ResponseWriter, r *http.Request) {
	// r.Context() se cancela si el cliente corta la conexión: pasándolo
	// hacia abajo, la consulta a Postgres se cancela también.
	programs, err := h.cat.ListPrograms(r.Context())
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, programs)
}

func (h catalogHandlers) getProgram(w http.ResponseWriter, r *http.Request) {
	// PathValue lee el wildcard {slug} del patrón: el @PathVariable de Go.
	program, err := h.cat.GetProgram(r.Context(), r.PathValue("slug"))
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, program)
}

func (h catalogHandlers) getSession(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "id de sesión inválido"})
		return
	}
	session, err := h.cat.GetSession(r.Context(), id)
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, session)
}

type errorResponse struct {
	Error string `json:"error"`
}

// writeError traduce un error a una respuesta HTTP: el @ControllerAdvice de
// esta API. Los errores conocidos tienen su status; el resto es un 500, que
// se loguea con el detalle y al cliente le llega un mensaje genérico (el
// detalle puede tener información interna, como el SQL).
func writeError(w http.ResponseWriter, r *http.Request, err error) {
	// errors.Is recorre la cadena de errores envueltos con %w: encuentra
	// ErrNotFound o context.DeadlineExceeded aunque estén varias capas abajo.
	switch {
	case errors.Is(err, catalog.ErrNotFound):
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "no encontrado"})
		return
	case errors.Is(err, context.DeadlineExceeded):
		// Venció el timeout del request (middleware withTimeout).
		slog.Warn("timeout atendiendo el request", "method", r.Method, "path", r.URL.Path, "err", err)
		writeJSON(w, http.StatusGatewayTimeout, errorResponse{Error: "tiempo agotado"})
		return
	case errors.Is(err, context.Canceled):
		// El cliente cortó la conexión: no hay a quién responder, y no es
		// un error del servidor.
		slog.Info("el cliente canceló el request", "method", r.Method, "path", r.URL.Path)
		return
	}
	slog.Error("error atendiendo el request", "method", r.Method, "path", r.URL.Path, "err", err)
	writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "error interno"})
}

// writeJSON serializa v como JSON con el status indicado.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		// Los headers ya se enviaron: lo único posible es loguear.
		slog.Error("escribiendo respuesta JSON", "err", err)
	}
}
