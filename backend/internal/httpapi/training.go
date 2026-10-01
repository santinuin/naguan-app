package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/santinuin/naguan-app/backend/internal/auth"
	"github.com/santinuin/naguan-app/backend/internal/training"
)

// trainingHandlers son los endpoints del usuario: su progreso en cada Senda,
// sus Fraguas templadas, la Brasa y los Mojones. Todos leen el usuario del
// contexto (lo dejó requireUser).
type trainingHandlers struct {
	tr Training
}

// userID saca el id del usuario autenticado. Si no está, es un error de
// cableado (requireUser no corrió), no del cliente.
func userID(r *http.Request) (string, error) {
	u, ok := auth.UserFrom(r.Context())
	if !ok {
		return "", errors.New("request sin usuario en el contexto")
	}
	return u.ID, nil
}

func (h trainingHandlers) listProgress(w http.ResponseWriter, r *http.Request) {
	uid, err := userID(r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	progress, err := h.tr.ListProgress(r.Context(), uid)
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, progress)
}

func (h trainingHandlers) getProgress(w http.ResponseWriter, r *http.Request) {
	uid, err := userID(r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	progress, err := h.tr.Progress(r.Context(), uid, r.PathValue("slug"))
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, progress)
}

// resetProgress es un DELETE sobre "el progreso" de la Senda: lo que se
// borra son los checks (el recurso), no la Senda ni el historial.
func (h trainingHandlers) resetProgress(w http.ResponseWriter, r *http.Request) {
	uid, err := userID(r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	if err := h.tr.ResetProgress(r.Context(), uid, r.PathValue("slug")); err != nil {
		writeError(w, r, err)
		return
	}
	// 204: salió bien y no hay nada que devolver.
	w.WriteHeader(http.StatusNoContent)
}

func (h trainingHandlers) recordWorkout(w http.ResponseWriter, r *http.Request) {
	uid, err := userID(r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	var req training.NewWorkout
	if err := readJSON(w, r, &req); err != nil {
		writeError(w, r, err)
		return
	}
	created, err := h.tr.RecordWorkout(r.Context(), uid, req)
	if err != nil {
		writeError(w, r, err)
		return
	}
	// 201 Created: se creó un recurso nuevo.
	writeJSON(w, http.StatusCreated, created)
}

const (
	defaultWorkoutsLimit = 20
	maxWorkoutsLimit     = 100
)

func (h trainingHandlers) listWorkouts(w http.ResponseWriter, r *http.Request) {
	uid, err := userID(r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	limit := defaultWorkoutsLimit
	// r.URL.Query() parsea el query string: ?limit=50 (el @RequestParam).
	if v := r.URL.Query().Get("limit"); v != "" {
		limit, err = strconv.Atoi(v)
		if err != nil || limit < 1 || limit > maxWorkoutsLimit {
			writeError(w, r, badRequest(fmt.Sprintf("limit tiene que ser un número entre 1 y %d", maxWorkoutsLimit)))
			return
		}
	}
	workouts, err := h.tr.ListWorkouts(r.Context(), uid, int32(limit))
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, workouts)
}

// getStats necesita el día de hoy del usuario (?today=AAAA-MM-DD): la Brasa
// se cuenta en días locales, y el servidor no sabe en qué zona horaria está
// el teléfono.
func (h trainingHandlers) getStats(w http.ResponseWriter, r *http.Request) {
	uid, err := userID(r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	today, err := time.Parse(time.DateOnly, r.URL.Query().Get("today"))
	if err != nil {
		writeError(w, r, badRequest("falta today con el formato AAAA-MM-DD"))
		return
	}
	// Sanidad: el "hoy" del teléfono no puede estar lejos de la fecha UTC
	// (las zonas horarias van de UTC-12 a UTC+14).
	utcToday := time.Now().UTC().Truncate(24 * time.Hour)
	if d := today.Sub(utcToday); d < -48*time.Hour || d > 48*time.Hour {
		writeError(w, r, badRequest("today no coincide con la fecha actual"))
		return
	}
	stats, err := h.tr.Stats(r.Context(), uid, today)
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

func (h trainingHandlers) listRecords(w http.ResponseWriter, r *http.Request) {
	uid, err := userID(r)
	if err != nil {
		writeError(w, r, err)
		return
	}
	records, err := h.tr.Records(r.Context(), uid)
	if err != nil {
		writeError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, records)
}

// maxBodyBytes acota el tamaño del cuerpo: sin límite, un cliente podría
// mandar gigas y agotar la memoria del servidor.
const maxBodyBytes = 1 << 20 // 1 MiB

// readJSON decodifica el cuerpo del request en dst (el @RequestBody). Es
// estricto a propósito: un campo desconocido o JSON de más es un 400, así un
// error de tipeo en la app ("sesion_id") no pasa en silencio.
func readJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return badRequest("cuerpo JSON inválido: " + err.Error())
	}
	// Un segundo Decode tiene que dar EOF: si no, venía más de un objeto.
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return badRequest("el cuerpo tiene que ser un único objeto JSON")
	}
	return nil
}

// badRequestError es un request mal formado (JSON inválido, un parámetro
// fuera de rango): un problema de HTTP, no del dominio. Por eso es de este
// paquete y no reutiliza training.ValidationError.
type badRequestError struct{ msg string }

func (e *badRequestError) Error() string { return e.msg }

func badRequest(msg string) error { return &badRequestError{msg: msg} }
