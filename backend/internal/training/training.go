// Package training maneja lo que entrena cada usuario.
//
// El modelo es flexible: el usuario templa cualquier Fragua (sesión) de
// cualquier Senda (programa), en cualquier orden y las veces que quiera. Cada
// una queda como un workout, y todo lo demás se deriva de ahí: el progreso de
// cada Senda (checks y próxima sugerida), la Brasa y los Mojones.
//
// Todas las operaciones reciben el userID, que sale del token verificado
// (auth.UserFrom): nunca de un dato que mande la app.
package training

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/santinuin/naguan-app/backend/internal/db"
)

// ErrProgramNotFound: no existe la Senda pedida.
var ErrProgramNotFound = errors.New("no existe la senda")

// ValidationError es un problema con los datos que mandó la app (un 400). Es
// un tipo y no una variable como ErrProgramNotFound porque lleva un mensaje
// distinto cada vez; los handlers lo detectan con errors.As.
type ValidationError struct {
	Msg string
}

func (e *ValidationError) Error() string { return e.Msg }

func invalid(format string, args ...any) error {
	return &ValidationError{Msg: fmt.Sprintf(format, args...)}
}

// ── Tipos de respuesta ───────────────────────────────────────────────────────

type ProgramRef struct {
	Slug string `json:"slug"`
	Name string `json:"name"`
}

type SessionRef struct {
	Position int16  `json:"position,omitempty"`
	ID       int64  `json:"id"`
	Title    string `json:"title"`
}

// ProgramProgress es el avance del usuario en una Senda.
type ProgramProgress struct {
	Program   ProgramRef `json:"program"`
	Completed int64      `json:"completed_sessions"`
	Total     int64      `json:"total_sessions"`
	// Next es la próxima Fragua sugerida (la primera sin check); null si la
	// Senda está completa.
	Next *SessionRef `json:"next_session"`
	// ResetAt es el último reset; null si nunca se reseteó.
	ResetAt *time.Time `json:"reset_at"`
}

// ProgramProgressDetail es el progreso de una Senda más los ids de sus
// Fraguas con check.
//
// ProgramProgress va embebido (campo sin nombre): en JSON sus campos se
// aplanan al mismo nivel, como si estuvieran escritos acá. Así la lista y el
// detalle comparten forma, y el detalle suma un campo. (Con `omitempty` en un
// solo tipo no alcanzaba: Go omite también los slices vacíos, y una Senda
// recién reseteada mandaría el campo ausente en vez de [].)
type ProgramProgressDetail struct {
	ProgramProgress
	CompletedSessionIDs []int64 `json:"completed_session_ids"`
}

// Workout es una Fragua templada.
type Workout struct {
	ID         int64       `json:"id"`
	Session    SessionRef  `json:"session"`
	Program    *ProgramRef `json:"program"` // null si la sesión no es de ninguna Senda
	StartedAt  time.Time   `json:"started_at"`
	FinishedAt time.Time   `json:"finished_at"`
	LocalDate  string      `json:"local_date"`
	DurationS  int64       `json:"duration_s"`
	// NewRecords son los Mojones superados en esta Fragua (solo al crearla).
	NewRecords []Record `json:"new_records,omitempty"`
}

// Record es un Mojón: la mejor marca en un ejercicio, en reps o en segundos.
type Record struct {
	Exercise string `json:"exercise"`
	// Metric es "reps" o "duration_s".
	Metric string `json:"metric"`
	Value  int32  `json:"value"`
	// Previous es la marca anterior (solo en los Mojones nuevos).
	Previous int32 `json:"previous,omitempty"`
}

// Stats es el resumen del usuario.
type Stats struct {
	Brasa         Brasa `json:"brasa"`
	TotalWorkouts int64 `json:"total_workouts"`
}

// ── Servicio ─────────────────────────────────────────────────────────────────

// Service necesita el pool (y no solo *db.Queries) porque abre transacciones.
type Service struct {
	pool *pgxpool.Pool
	q    *db.Queries
}

func NewService(pool *pgxpool.Pool) *Service {
	return &Service{pool: pool, q: db.New(pool)}
}

// inTx corre fn dentro de una transacción: si fn devuelve error, se deshace
// todo (rollback); si no, se confirma (commit). Es lo que en Spring hace
// @Transactional, pero explícito: se ve dónde empieza y dónde termina.
func (s *Service) inTx(ctx context.Context, fn func(q *db.Queries) error) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("abriendo la transacción: %w", err)
	}
	// Rollback después de un Commit exitoso no hace nada: así, con un solo
	// defer, cualquier salida temprana (un error, un panic) deshace la
	// transacción.
	defer tx.Rollback(ctx)

	// WithTx devuelve unas Queries que usan la transacción en vez del pool:
	// el mismo código de consultas, dentro o fuera de una transacción.
	if err := fn(s.q.WithTx(tx)); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func progressFromRow(r db.ListProgramProgressRow) ProgramProgress {
	p := ProgramProgress{
		Program:   ProgramRef{Slug: r.Slug, Name: r.Name},
		Completed: r.CompletedSessions,
		Total:     r.TotalSessions,
	}
	if r.ResetAt != nil {
		t := r.ResetAt.UTC()
		p.ResetAt = &t
	}
	// 0 es el centinela de la consulta: no hay próxima (Senda completa).
	if r.NextSessionID != 0 {
		p.Next = &SessionRef{Position: r.NextPosition, ID: r.NextSessionID, Title: r.NextTitle}
	}
	return p
}

// ListProgress devuelve el avance del usuario en todas las Sendas.
func (s *Service) ListProgress(ctx context.Context, userID string) ([]ProgramProgress, error) {
	rows, err := s.q.ListProgramProgress(ctx, db.ListProgramProgressParams{UserID: userID})
	if err != nil {
		return nil, fmt.Errorf("leyendo el progreso: %w", err)
	}
	out := make([]ProgramProgress, 0, len(rows))
	for _, r := range rows {
		out = append(out, progressFromRow(r))
	}
	return out, nil
}

// Progress devuelve el avance en una Senda, con los ids de las Fraguas con
// check.
func (s *Service) Progress(ctx context.Context, userID, slug string) (ProgramProgressDetail, error) {
	rows, err := s.q.ListProgramProgress(ctx, db.ListProgramProgressParams{UserID: userID, Slug: &slug})
	if err != nil {
		return ProgramProgressDetail{}, fmt.Errorf("leyendo el progreso de %q: %w", slug, err)
	}
	if len(rows) == 0 {
		return ProgramProgressDetail{}, ErrProgramNotFound
	}
	ids, err := s.q.ListCompletedSessions(ctx, db.ListCompletedSessionsParams{UserID: userID, ProgramID: rows[0].ID})
	if err != nil {
		return ProgramProgressDetail{}, fmt.Errorf("leyendo las fraguas templadas de %q: %w", slug, err)
	}
	return ProgramProgressDetail{
		ProgramProgress: progressFromRow(rows[0]),
		// Un slice vacío (no nil): json.Marshal escribe [] y no null.
		CompletedSessionIDs: append([]int64{}, ids...),
	}, nil
}

// ResetProgress limpia los checks de una Senda. El historial no se borra.
func (s *Service) ResetProgress(ctx context.Context, userID, slug string) error {
	p, err := s.q.GetProgramBySlug(ctx, slug)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrProgramNotFound
	}
	if err != nil {
		return fmt.Errorf("leyendo el programa %q: %w", slug, err)
	}
	if err := s.q.ResetProgramProgress(ctx, db.ResetProgramProgressParams{UserID: userID, ProgramID: p.ID}); err != nil {
		return fmt.Errorf("reseteando %q: %w", slug, err)
	}
	return nil
}

// NewWorkout es lo que manda la app al terminar una Fragua.
type NewWorkout struct {
	SessionID  int64        `json:"session_id"`
	StartedAt  time.Time    `json:"started_at"`
	FinishedAt time.Time    `json:"finished_at"`
	LocalDate  string       `json:"local_date"` // "2026-10-01", el día en el teléfono
	Items      []ItemResult `json:"items"`
}

// ItemResult es lo que el usuario hizo en un ejercicio de la Fragua.
type ItemResult struct {
	BlockItemID int64  `json:"block_item_id"`
	Reps        *int16 `json:"reps"`
	DurationS   *int32 `json:"duration_s"`
}

const maxWorkoutDuration = 12 * time.Hour

// validate revisa lo que se puede revisar sin la base: fechas, duplicados y
// valores. Es una función pura, así que se testea sin Postgres.
//
// Recibe la hora actual (now) en vez de llamar a time.Now() adentro: así el
// resultado depende solo de sus argumentos y los tests no dependen del
// momento en que se corren (inyectar el reloj, como un java.time.Clock).
func (w NewWorkout) validate(now time.Time) (localDate time.Time, err error) {
	if w.SessionID <= 0 {
		return time.Time{}, invalid("falta session_id")
	}
	if w.StartedAt.IsZero() || w.FinishedAt.IsZero() {
		return time.Time{}, invalid("faltan started_at o finished_at")
	}
	if w.FinishedAt.Before(w.StartedAt) {
		return time.Time{}, invalid("finished_at es anterior a started_at")
	}
	if w.FinishedAt.Sub(w.StartedAt) > maxWorkoutDuration {
		return time.Time{}, invalid("una fragua no puede durar más de %v", maxWorkoutDuration)
	}
	if w.FinishedAt.After(now.Add(5 * time.Minute)) {
		return time.Time{}, invalid("finished_at está en el futuro")
	}
	// time.Parse usa una fecha de referencia como plantilla del formato
	// (2006-01-02): en vez de "yyyy-MM-dd", se escribe cómo se vería esa
	// fecha concreta. Es una rareza de Go que se aprende una vez.
	localDate, err = time.Parse(time.DateOnly, w.LocalDate)
	if err != nil {
		return time.Time{}, invalid("local_date tiene que tener el formato AAAA-MM-DD")
	}
	// El día local puede diferir del día UTC por la zona horaria, pero
	// nunca en más de un día.
	utcDay := w.FinishedAt.UTC().Truncate(24 * time.Hour)
	if d := localDate.Sub(utcDay); d < -24*time.Hour || d > 24*time.Hour {
		return time.Time{}, invalid("local_date no coincide con finished_at")
	}

	seen := make(map[int64]bool, len(w.Items))
	for _, it := range w.Items {
		switch {
		case seen[it.BlockItemID]:
			return time.Time{}, invalid("el ítem %d está repetido", it.BlockItemID)
		case it.Reps == nil && it.DurationS == nil:
			return time.Time{}, invalid("el ítem %d no tiene reps ni duration_s", it.BlockItemID)
		case (it.Reps != nil && *it.Reps < 0) || (it.DurationS != nil && *it.DurationS < 0):
			return time.Time{}, invalid("el ítem %d tiene valores negativos", it.BlockItemID)
		}
		seen[it.BlockItemID] = true
	}
	return localDate, nil
}

// RecordWorkout registra una Fragua templada y devuelve los Mojones que
// superó.
func (s *Service) RecordWorkout(ctx context.Context, userID string, w NewWorkout) (Workout, error) {
	localDate, err := w.validate(time.Now())
	if err != nil {
		return Workout{}, err
	}

	var out Workout
	err = s.inTx(ctx, func(q *db.Queries) error {
		session, err := q.GetSession(ctx, w.SessionID)
		if errors.Is(err, pgx.ErrNoRows) {
			return invalid("no existe la sesión %d", w.SessionID)
		}
		if err != nil {
			return fmt.Errorf("leyendo la sesión: %w", err)
		}

		// Los ítems tienen que ser ejercicios de ESTA sesión: si no, la
		// app podría registrar reps en ítems de otra sesión (o en un
		// descanso).
		sessionItems, err := q.ListSessionItemsForWorkout(ctx, w.SessionID)
		if err != nil {
			return fmt.Errorf("leyendo los ítems de la sesión: %w", err)
		}
		byID := make(map[int64]db.ListSessionItemsForWorkoutRow, len(sessionItems))
		for _, it := range sessionItems {
			byID[it.ID] = it
		}
		for _, it := range w.Items {
			si, ok := byID[it.BlockItemID]
			if !ok {
				return invalid("el ítem %d no es de la sesión %d", it.BlockItemID, w.SessionID)
			}
			if si.Kind != db.ItemKindExercise {
				return invalid("el ítem %d es un descanso", it.BlockItemID)
			}
		}

		// Las marcas previas se leen ANTES de insertar: si no, la Fragua
		// nueva se compararía contra sí misma.
		records, err := newRecords(ctx, q, userID, w.Items, byID)
		if err != nil {
			return err
		}

		id, err := q.CreateWorkout(ctx, db.CreateWorkoutParams{
			UserID: userID, SessionID: w.SessionID,
			StartedAt: w.StartedAt, FinishedAt: w.FinishedAt, LocalDate: localDate,
		})
		if err != nil {
			return fmt.Errorf("creando el workout: %w", err)
		}

		rows := make([]db.CreateWorkoutItemsParams, len(w.Items))
		for i, it := range w.Items {
			rows[i] = db.CreateWorkoutItemsParams{
				WorkoutID: id, BlockItemID: it.BlockItemID, Reps: it.Reps, DurationS: it.DurationS,
			}
		}
		if _, err := q.CreateWorkoutItems(ctx, rows); err != nil {
			return fmt.Errorf("guardando los ítems: %w", err)
		}

		out.ID = id
		out.Session = SessionRef{ID: session.ID, Title: session.Title}
		out.NewRecords = records
		return nil
	})
	if err != nil {
		return Workout{}, err
	}
	out.StartedAt, out.FinishedAt = w.StartedAt.UTC(), w.FinishedAt.UTC()
	out.LocalDate = w.LocalDate
	out.DurationS = int64(w.FinishedAt.Sub(w.StartedAt).Seconds())
	return out, nil
}

// newRecords compara lo que se hizo en esta Fragua con las marcas previas
// del usuario y devuelve los Mojones superados. La primera vez que se hace un
// ejercicio no cuenta como Mojón (no había marca que superar).
func newRecords(
	ctx context.Context, q *db.Queries, userID string,
	items []ItemResult, byID map[int64]db.ListSessionItemsForWorkoutRow,
) ([]Record, error) {
	// La mejor marca de ESTA Fragua por ejercicio (juntando ambos lados).
	type best struct {
		name           string
		reps, duration int32
	}
	current := map[int64]*best{}
	for _, it := range items {
		si := byID[it.BlockItemID]
		b := current[*si.ExerciseID]
		if b == nil {
			b = &best{name: *si.ExerciseName}
			current[*si.ExerciseID] = b
		}
		if it.Reps != nil {
			b.reps = max(b.reps, int32(*it.Reps))
		}
		if it.DurationS != nil {
			b.duration = max(b.duration, *it.DurationS)
		}
	}
	if len(current) == 0 {
		return nil, nil
	}

	ids := make([]int64, 0, len(current))
	for id := range current {
		ids = append(ids, id)
	}
	prev, err := q.BestResults(ctx, db.BestResultsParams{UserID: userID, ExerciseIds: ids})
	if err != nil {
		return nil, fmt.Errorf("leyendo las marcas previas: %w", err)
	}

	var out []Record
	for _, p := range prev {
		c := current[p.ExerciseID]
		if p.BestReps > 0 && c.reps > p.BestReps {
			out = append(out, Record{Exercise: c.name, Metric: "reps", Value: c.reps, Previous: p.BestReps})
		}
		if p.BestDurationS > 0 && c.duration > p.BestDurationS {
			out = append(out, Record{Exercise: c.name, Metric: "duration_s", Value: c.duration, Previous: p.BestDurationS})
		}
	}
	// Orden estable para la respuesta (las filas de la base no tienen orden).
	// cmp.Or devuelve el primer resultado distinto de 0: ordena por
	// ejercicio y, si empatan, por métrica (un Comparator.thenComparing).
	slices.SortFunc(out, func(a, b Record) int {
		return cmp.Or(cmp.Compare(a.Exercise, b.Exercise), cmp.Compare(a.Metric, b.Metric))
	})
	return out, nil
}

// ListWorkouts devuelve las últimas Fraguas templadas del usuario.
func (s *Service) ListWorkouts(ctx context.Context, userID string, limit int32) ([]Workout, error) {
	rows, err := s.q.ListWorkouts(ctx, db.ListWorkoutsParams{UserID: userID, MaxRows: limit})
	if err != nil {
		return nil, fmt.Errorf("listando workouts: %w", err)
	}
	out := make([]Workout, 0, len(rows))
	for _, r := range rows {
		w := Workout{
			ID:         r.ID,
			Session:    SessionRef{ID: r.SessionID, Title: r.SessionTitle},
			StartedAt:  r.StartedAt.UTC(),
			FinishedAt: r.FinishedAt.UTC(),
			LocalDate:  r.LocalDate.Format(time.DateOnly),
			DurationS:  int64(r.FinishedAt.Sub(r.StartedAt).Seconds()),
		}
		if r.ProgramSlug != "" { // '' = sesión sin Senda (ver la consulta)
			w.Program = &ProgramRef{Slug: r.ProgramSlug, Name: r.ProgramName}
		}
		out = append(out, w)
	}
	return out, nil
}

// Stats devuelve el resumen del usuario: la Brasa y el total de Fraguas.
// today es el día de hoy en el teléfono del usuario (como local_date).
func (s *Service) Stats(ctx context.Context, userID string, today time.Time) (Stats, error) {
	trainedDays, err := s.q.ListTrainingDays(ctx, db.ListTrainingDaysParams{UserID: userID, Today: today})
	if err != nil {
		return Stats{}, fmt.Errorf("leyendo los días entrenados: %w", err)
	}
	total, err := s.q.CountWorkouts(ctx, userID)
	if err != nil {
		return Stats{}, fmt.Errorf("contando workouts: %w", err)
	}
	return Stats{Brasa: computeBrasa(trainedDays, today), TotalWorkouts: total}, nil
}

// Records devuelve los Mojones del usuario: su mejor marca en cada ejercicio
// que hizo, en reps y/o en segundos.
func (s *Service) Records(ctx context.Context, userID string) ([]Record, error) {
	rows, err := s.q.ListRecords(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("leyendo los mojones: %w", err)
	}
	out := []Record{}
	for _, r := range rows {
		if r.BestReps > 0 {
			out = append(out, Record{Exercise: r.Name, Metric: "reps", Value: r.BestReps})
		}
		if r.BestDurationS > 0 {
			out = append(out, Record{Exercise: r.Name, Metric: "duration_s", Value: r.BestDurationS})
		}
	}
	return out, nil
}
