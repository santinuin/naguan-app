// Package httpapi contiene el router HTTP y los handlers de la API.
package httpapi

import (
	"encoding/json"
	"log/slog"
	"net/http"
)

// NewRouter arma el mux con todas las rutas. Devuelve http.Handler (y no
// *http.ServeMux) para que main y los tests dependan solo de la interfaz.
func NewRouter() http.Handler {
	mux := http.NewServeMux()

	// Desde Go 1.22 el mux soporta método y wildcards en el patrón,
	// así que por ahora no hace falta Chi ni Gin.
	mux.HandleFunc("GET /health", handleHealth)

	return mux
}

type healthResponse struct {
	Status string `json:"status"`
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, healthResponse{Status: "ok"})
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
