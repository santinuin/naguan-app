// Package config carga la configuración del servidor desde variables de
// entorno, una sola vez al arrancar. Es el @ConfigurationProperties de este
// proyecto: un struct tipado, con valores por defecto y validación, en vez de
// os.Getenv desparramado por el código.
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	// Port es el puerto HTTP. Cloud Run lo inyecta en PORT.
	Port string
	// DatabaseURL es la conexión a Postgres (el spring.datasource.url).
	DatabaseURL string
	// RequestTimeout es el tiempo máximo para atender un request: pasado
	// ese tiempo se cancela su contexto (y con él, las consultas en curso).
	RequestTimeout time.Duration
	// ShutdownTimeout es cuánto se espera a los requests en curso al apagar.
	ShutdownTimeout time.Duration
}

// localDatabaseURL es el Postgres de `supabase start`.
const localDatabaseURL = "postgres://postgres:postgres@127.0.0.1:54322/postgres"

// Load lee la configuración del entorno del proceso.
func Load() (Config, error) {
	return load(os.LookupEnv)
}

// load recibe la función que busca una variable, en vez de llamar a
// os.LookupEnv directamente: así los tests le pasan un map y no dependen del
// entorno real. En Go las funciones son valores, y pasar una función es la
// forma más liviana de inyectar una dependencia.
func load(lookup func(string) (string, bool)) (Config, error) {
	get := func(key, def string) string {
		if v, ok := lookup(key); ok && v != "" {
			return v
		}
		return def
	}

	cfg := Config{
		Port:        get("PORT", "8080"),
		DatabaseURL: get("DATABASE_URL", localDatabaseURL),
	}

	// Como en el importador, se juntan todos los errores: si faltan tres
	// cosas, el mensaje dice las tres.
	var errs []error
	if p, err := strconv.Atoi(cfg.Port); err != nil || p < 1 || p > 65535 {
		errs = append(errs, fmt.Errorf("PORT inválido: %q", cfg.Port))
	}
	var err error
	if cfg.RequestTimeout, err = duration(get("REQUEST_TIMEOUT", "10s")); err != nil {
		errs = append(errs, fmt.Errorf("REQUEST_TIMEOUT: %w", err))
	}
	if cfg.ShutdownTimeout, err = duration(get("SHUTDOWN_TIMEOUT", "10s")); err != nil {
		errs = append(errs, fmt.Errorf("SHUTDOWN_TIMEOUT: %w", err))
	}
	return cfg, errors.Join(errs...)
}

// duration acepta el formato de Go: "500ms", "10s", "1m30s".
func duration(s string) (time.Duration, error) {
	d, err := time.ParseDuration(s)
	if err != nil {
		return 0, fmt.Errorf("%q no es una duración (ej.: 10s, 500ms)", s)
	}
	if d <= 0 {
		return 0, fmt.Errorf("%q debe ser positiva", s)
	}
	return d, nil
}
