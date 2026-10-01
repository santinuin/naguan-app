// Command api es el servidor HTTP del backend.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/santinuin/naguan-app/backend/internal/catalog"
	"github.com/santinuin/naguan-app/backend/internal/db"
	"github.com/santinuin/naguan-app/backend/internal/httpapi"
)

// localDatabaseURL es el Postgres de `supabase start`. En Cloud Run se usa
// DATABASE_URL (el equivalente a spring.datasource.url).
const localDatabaseURL = "postgres://postgres:postgres@127.0.0.1:54322/postgres"

func main() {
	if err := run(); err != nil {
		slog.Error("el servidor terminó con error", "err", err)
		os.Exit(1)
	}
}

func run() error {
	// Cloud Run inyecta el puerto en PORT; en local usamos 8080.
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = localDatabaseURL
	}

	// El pool de conexiones (el HikariCP de pgx). pgxpool.New no se conecta
	// todavía: Ping verifica al arrancar que la base responde, para fallar
	// rápido en vez de en el primer request.
	startCtx, cancelStart := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelStart()
	pool, err := pgxpool.New(startCtx, dbURL)
	if err != nil {
		return fmt.Errorf("configurando el pool de Postgres: %w", err)
	}
	// defer corre al salir de run(): cierra las conexiones después del
	// shutdown del servidor (los defer se ejecutan en orden inverso).
	defer pool.Close()
	if err := pool.Ping(startCtx); err != nil {
		return fmt.Errorf("conectando a Postgres: %w", err)
	}

	// El "contenedor de dependencias", a mano: cada pieza recibe lo que
	// necesita por constructor.
	queries := db.New(pool)
	catalogService := catalog.NewService(queries)
	router := httpapi.NewRouter(catalogService)

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	// ctx se cancela al recibir Ctrl+C (SIGINT) o SIGTERM. Cloud Run manda
	// SIGTERM antes de apagar una instancia, y queremos terminar limpio.
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	errCh := make(chan error, 1)
	go func() {
		slog.Info("escuchando", "addr", srv.Addr)
		// ListenAndServe siempre devuelve error; ErrServerClosed es el apagado normal.
		if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		slog.Info("apagando...")
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}
