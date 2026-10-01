package config

import (
	"strings"
	"testing"
	"time"
)

// env arma una función de búsqueda a partir de un map: el "entorno" del test.
func env(vars map[string]string) func(string) (string, bool) {
	return func(key string) (string, bool) {
		v, ok := vars[key]
		return v, ok
	}
}

func TestLoadDefaults(t *testing.T) {
	cfg, err := load(env(nil))
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	want := Config{
		Port:            "8080",
		DatabaseURL:     localDatabaseURL,
		SupabaseURL:     localSupabaseURL,
		SupabaseIssuer:  localSupabaseURL + "/auth/v1",
		RequestTimeout:  10 * time.Second,
		ShutdownTimeout: 10 * time.Second,
	}
	// Los structs con campos comparables se comparan con ==, campo a campo.
	if cfg != want {
		t.Errorf("cfg = %+v\nwant  %+v", cfg, want)
	}
}

func TestLoadFromEnv(t *testing.T) {
	cfg, err := load(env(map[string]string{
		"PORT":            "9000",
		"DATABASE_URL":    "postgres://otra",
		"REQUEST_TIMEOUT": "2s",
	}))
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if cfg.Port != "9000" || cfg.DatabaseURL != "postgres://otra" || cfg.RequestTimeout != 2*time.Second {
		t.Errorf("cfg = %+v", cfg)
	}
}

func TestLoadReportsAllErrors(t *testing.T) {
	_, err := load(env(map[string]string{
		"PORT":             "ochenta",
		"REQUEST_TIMEOUT":  "diez",
		"SHUTDOWN_TIMEOUT": "-1s",
	}))
	if err == nil {
		t.Fatal("se esperaba un error")
	}
	for _, want := range []string{"PORT", "REQUEST_TIMEOUT", "SHUTDOWN_TIMEOUT"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("el error no menciona %s: %v", want, err)
		}
	}
}

func TestIssuerOverride(t *testing.T) {
	cfg, err := load(env(map[string]string{
		"SUPABASE_URL":    "http://host.docker.internal:54321",
		"SUPABASE_ISSUER": "http://127.0.0.1:54321/auth/v1",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.SupabaseIssuer != "http://127.0.0.1:54321/auth/v1" {
		t.Errorf("issuer = %q", cfg.SupabaseIssuer)
	}
}
