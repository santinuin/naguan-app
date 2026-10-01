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

	"github.com/santinuin/naguan-app/backend/internal/auth"
	"github.com/santinuin/naguan-app/backend/internal/catalog"
	"github.com/santinuin/naguan-app/backend/internal/training"
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

// Training es lo que los handlers necesitan del registro de entrenamiento.
type Training interface {
	ListProgress(ctx context.Context, userID string) ([]training.ProgramProgress, error)
	Progress(ctx context.Context, userID, slug string) (training.ProgramProgressDetail, error)
	ResetProgress(ctx context.Context, userID, slug string) error
	RecordWorkout(ctx context.Context, userID string, w training.NewWorkout) (w2 training.Workout, created bool, err error)
	ListWorkouts(ctx context.Context, userID string, limit int32) ([]training.Workout, error)
	Stats(ctx context.Context, userID string, today time.Time) (training.Stats, error)
	Records(ctx context.Context, userID string) ([]training.Record, error)
}

// Deps son las dependencias del router. Un struct en vez de una lista de
// parámetros: con cuatro o más, los nombres de campo hacen legible la
// llamada (Deps{Catalog: ..., Training: ...}) y agregar uno no rompe el orden.
type Deps struct {
	Catalog        Catalog
	Training       Training
	Verifier       TokenVerifier
	RequestTimeout time.Duration
}

// NewRouter arma el mux con todas las rutas y le aplica el middleware.
// Devuelve http.Handler (y no *http.ServeMux) para que main y los tests
// dependan solo de la interfaz.
func NewRouter(d Deps) http.Handler {
	// La API de la app (/v1) vive en su propio mux, y todo él pasa por
	// requireUser: el contenido de los programas solo lo ve quien inició
	// sesión. Desde Go 1.22 el mux soporta método y wildcards en el patrón;
	// no hace falta Chi ni Gin.
	v1 := http.NewServeMux()
	c := catalogHandlers{cat: d.Catalog}
	v1.HandleFunc("GET /v1/programs", c.listPrograms)
	v1.HandleFunc("GET /v1/programs/{slug}", c.getProgram)
	v1.HandleFunc("GET /v1/sessions/{id}", c.getSession)

	// Lo que es del usuario va bajo /v1/me: la ruta deja claro que el
	// recurso es "el mío", y el usuario sale del token, nunca de la URL
	// (no hay /v1/users/{id} que alguien pueda cambiar por otro id).
	t := trainingHandlers{tr: d.Training}
	v1.HandleFunc("GET /v1/me", handleMe)
	v1.HandleFunc("GET /v1/me/programs", t.listProgress)
	v1.HandleFunc("GET /v1/me/programs/{slug}", t.getProgress)
	v1.HandleFunc("DELETE /v1/me/programs/{slug}/progress", t.resetProgress)
	v1.HandleFunc("POST /v1/me/workouts", t.recordWorkout)
	v1.HandleFunc("GET /v1/me/workouts", t.listWorkouts)
	v1.HandleFunc("GET /v1/me/stats", t.getStats)
	v1.HandleFunc("GET /v1/me/records", t.listRecords)

	mux := http.NewServeMux()
	// /health es público y sin versión: lo consulta la infraestructura
	// (Cloud Run, un balanceador), no la app.
	mux.HandleFunc("GET /health", handleHealth)
	// Un patrón que termina en "/" captura todo lo que empieza así. Las
	// rutas bajo /v1 van versionadas: cuando haya que romper el contrato,
	// conviven /v1 y /v2 mientras la app se actualiza.
	mux.Handle("/v1/", requireUser(d.Verifier)(v1))

	// El orden importa: logRequests va afuera de todo para registrar
	// también los 500 que genera recoverPanics.
	return chain(mux,
		logRequests,
		recoverPanics,
		withTimeout(d.RequestTimeout),
	)
}

type meResponse struct {
	ID    string `json:"id"`
	Email string `json:"email"`
}

// handleMe devuelve el usuario del token: sirve para que la app (y nosotros)
// verifiquen que la autenticación funciona de punta a punta.
func handleMe(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.UserFrom(r.Context())
	if !ok {
		// No debería pasar: requireUser corre antes. Si pasa, es un bug de
		// cableado de rutas, no un error del cliente.
		writeError(w, r, errors.New("handleMe sin usuario en el contexto"))
		return
	}
	writeJSON(w, http.StatusOK, meResponse{ID: user.ID, Email: user.Email})
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
	// errors.As busca en la cadena un error de un TIPO (no un valor
	// puntual, como errors.Is): para errores que llevan datos, como el
	// mensaje de una validación.
	var verr *training.ValidationError
	var berr *badRequestError
	switch {
	case errors.As(err, &verr):
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: verr.Msg})
		return
	case errors.As(err, &berr):
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: berr.msg})
		return
	case errors.Is(err, catalog.ErrNotFound):
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "no encontrado"})
		return
	case errors.Is(err, training.ErrUnknownUser):
		// Token válido de una cuenta que ya no existe: que la app vuelva a
		// iniciar sesión.
		unauthorized(w, "el usuario no existe")
		return
	case errors.Is(err, training.ErrProgramNotFound):
		writeJSON(w, http.StatusNotFound, errorResponse{Error: "no existe la senda"})
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
