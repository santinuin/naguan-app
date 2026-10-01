// Package catalog expone el catálogo de programas y sesiones para la API:
// lee con las consultas generadas por sqlc (paquete db) y arma los tipos de
// respuesta.
package catalog

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"

	"github.com/santinuin/naguan-app/backend/internal/db"
)

// ErrNotFound indica que el recurso pedido no existe. Los handlers lo
// traducen a un 404 con errors.Is; es el equivalente a lanzar una
// NotFoundException y mapearla en un @ControllerAdvice, pero explícito.
var ErrNotFound = errors.New("no encontrado")

// ── Tipos de respuesta (lo que se serializa a JSON) ──────────────────────────
//
// Están separados de las filas de db a propósito, como separar la entidad
// del DTO en Spring: el esquema puede cambiar sin romper la API, y la forma
// de la respuesta (p. ej. una sesión con sus bloques anidados) no tiene por
// qué parecerse a una tabla.

type ProgramSummary struct {
	Slug         string  `json:"slug"`
	Name         string  `json:"name"`
	Description  *string `json:"description"`
	SessionCount int64   `json:"session_count"`
}

type Program struct {
	Slug        string           `json:"slug"`
	Name        string           `json:"name"`
	Description *string          `json:"description"`
	Sessions    []SessionSummary `json:"sessions"`
}

type SessionSummary struct {
	Position int16  `json:"position"`
	ID       int64  `json:"id"`
	Kind     string `json:"kind"`
	Title    string `json:"title"`
}

type Session struct {
	ID          int64   `json:"id"`
	Kind        string  `json:"kind"`
	Title       string  `json:"title"`
	Description *string `json:"description"`
	Blocks      []Block `json:"blocks"`
}

type Block struct {
	Position int16  `json:"position"`
	Type     string `json:"type"`
	TimeCapS *int32 `json:"time_cap_s,omitempty"`
	Items    []Item `json:"items"`
}

type Item struct {
	// ID identifica el ítem: la app lo manda de vuelta al registrar una
	// Fragua templada, para decir qué hizo en cada ejercicio.
	ID        int64        `json:"id"`
	Round     int16        `json:"round"`
	Position  int16        `json:"position"`
	Kind      string       `json:"kind"`
	Exercise  *ExerciseRef `json:"exercise,omitempty"` // nil en los descansos
	Side      *string      `json:"side,omitempty"`
	DurationS *int32       `json:"duration_s,omitempty"`
	Reps      *int16       `json:"reps,omitempty"`
}

type ExerciseRef struct {
	Slug string `json:"slug"`
	Name string `json:"name"`
}

// ── Servicio ─────────────────────────────────────────────────────────────────

// Service lee el catálogo. Recibe *db.Queries por constructor: en Go no hay
// contenedor que lo inyecte, lo arma main.
type Service struct {
	q *db.Queries
}

func NewService(q *db.Queries) *Service {
	return &Service{q: q}
}

func (s *Service) ListPrograms(ctx context.Context) ([]ProgramSummary, error) {
	rows, err := s.q.ListPrograms(ctx)
	if err != nil {
		return nil, fmt.Errorf("listando programas: %w", err)
	}
	// make con capacidad = len(rows): reserva la memoria de una vez, como
	// new ArrayList<>(rows.size()).
	out := make([]ProgramSummary, 0, len(rows))
	for _, r := range rows {
		out = append(out, ProgramSummary{
			Slug: r.Slug, Name: r.Name, Description: r.Description, SessionCount: r.SessionCount,
		})
	}
	return out, nil
}

func (s *Service) GetProgram(ctx context.Context, slug string) (Program, error) {
	p, err := s.q.GetProgramBySlug(ctx, slug)
	if errors.Is(err, pgx.ErrNoRows) {
		return Program{}, ErrNotFound
	}
	if err != nil {
		return Program{}, fmt.Errorf("leyendo el programa %q: %w", slug, err)
	}

	rows, err := s.q.ListProgramSessions(ctx, p.ID)
	if err != nil {
		return Program{}, fmt.Errorf("listando las sesiones de %q: %w", slug, err)
	}
	out := Program{
		Slug: p.Slug, Name: p.Name, Description: p.Description,
		Sessions: make([]SessionSummary, 0, len(rows)),
	}
	for _, r := range rows {
		out.Sessions = append(out.Sessions, SessionSummary{
			Position: r.Position, ID: r.ID, Kind: string(r.Kind), Title: r.Title,
		})
	}
	return out, nil
}

func (s *Service) GetSession(ctx context.Context, id int64) (Session, error) {
	row, err := s.q.GetSession(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return Session{}, ErrNotFound
	}
	if err != nil {
		return Session{}, fmt.Errorf("leyendo la sesión %d: %w", id, err)
	}

	items, err := s.q.ListSessionItems(ctx, id)
	if err != nil {
		return Session{}, fmt.Errorf("leyendo los ítems de la sesión %d: %w", id, err)
	}
	return Session{
		ID: row.ID, Kind: string(row.Kind), Title: row.Title, Description: row.Description,
		Blocks: groupBlocks(items),
	}, nil
}

// groupBlocks arma los bloques a partir de las filas planas de
// ListSessionItems, que vienen ordenadas por bloque, vuelta y posición. Como
// están ordenadas, alcanza con una pasada: se abre un bloque nuevo cada vez
// que cambia block_position.
func groupBlocks(rows []db.ListSessionItemsRow) []Block {
	blocks := []Block{}
	for _, r := range rows {
		if len(blocks) == 0 || blocks[len(blocks)-1].Position != r.BlockPosition {
			blocks = append(blocks, Block{
				Position: r.BlockPosition, Type: string(r.BlockType), TimeCapS: r.TimeCapS,
			})
		}
		// Puntero al último bloque para modificarlo en el slice. Ojo: un
		// `b := blocks[i]` sería una copia (los structs se copian por valor,
		// no son referencias como los objetos de Java).
		b := &blocks[len(blocks)-1]

		it := Item{
			ID:    r.ItemID,
			Round: r.Round, Position: r.Position, Kind: string(r.Kind),
			DurationS: r.DurationS, Reps: r.Reps,
		}
		if r.ExerciseSlug != nil {
			it.Exercise = &ExerciseRef{Slug: *r.ExerciseSlug, Name: *r.ExerciseName}
		}
		if r.Side != nil {
			side := string(*r.Side)
			it.Side = &side
		}
		b.Items = append(b.Items, it)
	}
	return blocks
}
