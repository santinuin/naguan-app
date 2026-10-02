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

// Exercise es el detalle de un ejercicio: qué es, cómo se ve, qué trabaja y
// hacia dónde progresa.
type Exercise struct {
	Slug        string  `json:"slug"`
	Name        string  `json:"name"`
	Unilateral  bool    `json:"unilateral"`
	Description *string `json:"description"` // Markdown
	Videos      []Video `json:"videos"`
	Muscles     []Tag   `json:"muscles"`
	Joints      []Tag   `json:"joints"`
	// Vecinos directos en el grafo de progresiones.
	Easier []ExerciseRef `json:"easier"`
	Harder []ExerciseRef `json:"harder"`
}

// Video es la URL tal como está en la base (hoy, de YouTube). La API no la
// interpreta: si mañana los videos pasan a R2, cambia el dato y no el
// contrato.
type Video struct {
	Side *string `json:"side,omitempty"` // nil: vale para los dos lados
	URL  string  `json:"url"`
}

// Tag es un músculo o una articulación.
type Tag struct {
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

// GetExercise lee un ejercicio con todo lo que cuelga de él. Son cinco
// consultas chicas en secuencia, cada una por índice: unos milisegundos en
// total. Se podrían lanzar en paralelo con goroutines (errgroup, el Mono.zip
// de Go), pero a esta escala no hace falta y cada request ocuparía varias
// conexiones del pool a la vez.
func (s *Service) GetExercise(ctx context.Context, slug string) (Exercise, error) {
	e, err := s.q.GetExerciseBySlug(ctx, slug)
	if errors.Is(err, pgx.ErrNoRows) {
		return Exercise{}, ErrNotFound
	}
	if err != nil {
		return Exercise{}, fmt.Errorf("leyendo el ejercicio %q: %w", slug, err)
	}
	out := Exercise{
		Slug: e.Slug, Name: e.Name, Unilateral: e.Unilateral, Description: e.Description,
		// Slices vacíos y no nil: se serializan como [] y no como null, y
		// la app no tiene que distinguir los dos casos.
		Videos: []Video{}, Muscles: []Tag{}, Joints: []Tag{},
		Easier: []ExerciseRef{}, Harder: []ExerciseRef{},
	}

	videos, err := s.q.ListExerciseVideos(ctx, e.ID)
	if err != nil {
		return Exercise{}, fmt.Errorf("leyendo los videos de %q: %w", slug, err)
	}
	for _, v := range videos {
		video := Video{URL: v.Url}
		if v.Side != nil {
			side := string(*v.Side)
			video.Side = &side
		}
		out.Videos = append(out.Videos, video)
	}

	muscles, err := s.q.ListExerciseMuscles(ctx, e.ID)
	if err != nil {
		return Exercise{}, fmt.Errorf("leyendo los músculos de %q: %w", slug, err)
	}
	for _, m := range muscles {
		out.Muscles = append(out.Muscles, Tag{Slug: m.Slug, Name: m.Name})
	}

	joints, err := s.q.ListExerciseJoints(ctx, e.ID)
	if err != nil {
		return Exercise{}, fmt.Errorf("leyendo las articulaciones de %q: %w", slug, err)
	}
	for _, j := range joints {
		out.Joints = append(out.Joints, Tag{Slug: j.Slug, Name: j.Name})
	}

	progressions, err := s.q.ListExerciseProgressions(ctx, e.ID)
	if err != nil {
		return Exercise{}, fmt.Errorf("leyendo las progresiones de %q: %w", slug, err)
	}
	splitProgressions(&out, progressions)
	return out, nil
}

// splitProgressions reparte las filas de ListExerciseProgressions entre
// Easier y Harder. Recibe un puntero para modificar el Exercise del que
// llama (un struct pasado por valor sería una copia).
func splitProgressions(ex *Exercise, rows []db.ListExerciseProgressionsRow) {
	for _, r := range rows {
		ref := ExerciseRef{Slug: r.Slug, Name: r.Name}
		switch r.Direction {
		case "easier":
			ex.Easier = append(ex.Easier, ref)
		case "harder":
			ex.Harder = append(ex.Harder, ref)
		}
	}
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
