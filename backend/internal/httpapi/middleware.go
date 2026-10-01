package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"runtime/debug"
	"time"
)

// Middleware envuelve un handler con comportamiento extra (logging,
// recuperación de panics, timeouts...). Es el patrón decorator, y cumple el
// mismo papel que un WebFilter de WebFlux: cada uno decide qué hacer antes y
// después de llamar al siguiente (next).
type Middleware func(next http.Handler) http.Handler

// chain aplica los middlewares en orden: el primero de la lista es el más
// externo, el primero en ver el request y el último en ver la respuesta.
func chain(h http.Handler, mws ...Middleware) http.Handler {
	// Se envuelve de atrás para adelante para que el primero quede afuera.
	for i := len(mws) - 1; i >= 0; i-- {
		h = mws[i](h)
	}
	return h
}

// logRequests registra cada request al terminar: método, ruta, status,
// tamaño y duración.
func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w}

		next.ServeHTTP(rec, r)

		slog.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status, // 0 si el handler no escribió nada
			"bytes", rec.bytes,
			"duration", time.Since(start),
		)
	})
}

// statusRecorder es un http.ResponseWriter que además anota el status y los
// bytes escritos, para que logRequests los pueda leer después.
//
// El campo sin nombre `http.ResponseWriter` es *embedding*: statusRecorder
// "hereda" todos sus métodos (Header, Write, WriteHeader) y solo
// sobrescribe los que redefine. No es herencia como en Java: es composición
// con delegación automática, y el campo sigue accesible como
// rec.ResponseWriter.
type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (r *statusRecorder) WriteHeader(code int) {
	if r.status == 0 {
		r.status = code
	}
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	if r.status == 0 {
		// Escribir el cuerpo sin WriteHeader implica un 200, igual que en
		// net/http.
		r.status = http.StatusOK
	}
	n, err := r.ResponseWriter.Write(b)
	r.bytes += n
	return n, err
}

// Unwrap expone el writer original. http.ResponseController lo usa para
// llegar a funciones del writer real (como Flush) a través del envoltorio.
func (r *statusRecorder) Unwrap() http.ResponseWriter {
	return r.ResponseWriter
}

// recoverPanics convierte un panic en un handler en un 500 con el formato de
// error de la API, y lo loguea con el stack trace.
//
// Un panic en Go no es una excepción para el flujo normal: es un error de
// programación (un nil, un índice fuera de rango). net/http ya evita que un
// panic en un handler tumbe el servidor, pero corta la conexión sin
// responder; con este middleware el cliente recibe un 500 legible.
func recoverPanics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// defer + recover es la única forma de atrapar un panic: recover()
		// solo funciona dentro de una función diferida.
		defer func() {
			v := recover()
			if v == nil {
				return
			}
			// ErrAbortHandler es el panic que net/http usa a propósito para
			// abortar una respuesta: se deja seguir.
			if v == http.ErrAbortHandler {
				panic(v)
			}
			slog.Error("panic atendiendo el request",
				"method", r.Method, "path", r.URL.Path,
				"panic", v, "stack", string(debug.Stack()))
			writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "error interno"})
		}()
		next.ServeHTTP(w, r)
	})
}

// withTimeout le pone un deadline al contexto del request. No corta el
// handler a la fuerza (en Go no se puede matar una goroutine desde afuera):
// cancela el contexto, y todo lo que lo respeta (las consultas de pgx, un
// http.Client) se interrumpe y devuelve context.DeadlineExceeded.
func withTimeout(d time.Duration) Middleware {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ctx, cancel := context.WithTimeout(r.Context(), d)
			defer cancel()
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
