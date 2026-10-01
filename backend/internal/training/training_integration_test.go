package training

// Tests de integración: corren contra un Postgres real con el esquema y el
// seed cargados (el de `supabase start`). Se activan con TEST_DATABASE_URL:
//
//	TEST_DATABASE_URL=postgres://postgres:postgres@127.0.0.1:54322/postgres go test ./internal/training/
//
// Sin esa variable se saltean, para que `go test ./...` funcione sin base.

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// setup conecta a la base de test y crea un usuario descartable en
// auth.users; t.Cleanup lo borra al terminar (y on delete cascade se lleva
// sus enrollments y workouts).
func setup(t *testing.T) (*Service, *pgxpool.Pool, string) {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL no está definida: se saltea el test de integración")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)

	userID := newUUID()
	_, err = pool.Exec(ctx,
		`insert into auth.users (id, email) values ($1, $2)`, userID, "test-"+userID+"@naguan.local")
	if err != nil {
		t.Fatalf("creando el usuario de test: %v", err)
	}
	// t.Cleanup corre al final del test, en orden inverso al de registro
	// (como los defer): primero se borra el usuario, después se cierra el pool.
	t.Cleanup(func() {
		pool.Exec(context.Background(), `delete from auth.users where id = $1`, userID)
	})
	return NewService(pool), pool, userID
}

func newUUID() string {
	b := make([]byte, 16)
	rand.Read(b)
	b[6] = b[6]&0x0f | 0x40 // versión 4
	b[8] = b[8]&0x3f | 0x80 // variante RFC 4122
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

// sessionAt devuelve el id de la sesión en una posición de un programa, y el
// id de su primer ítem de ejercicio.
func sessionAt(t *testing.T, pool *pgxpool.Pool, program string, position int) (sessionID, exerciseItemID int64) {
	t.Helper()
	err := pool.QueryRow(context.Background(), `
		select ps.session_id, min(i.id)
		from program_session ps
		join program p on p.id = ps.program_id
		join block b on b.session_id = ps.session_id
		join block_item i on i.block_id = b.id and i.kind = 'exercise'
		where p.slug = $1 and ps.position = $2
		group by ps.session_id`, program, position).Scan(&sessionID, &exerciseItemID)
	if err != nil {
		t.Fatalf("buscando la sesión %d de %s: %v", position, program, err)
	}
	return sessionID, exerciseItemID
}

func workoutFor(sessionID int64, items ...ItemResult) NewWorkout {
	finished := time.Now().Add(-time.Minute).Truncate(time.Second)
	return NewWorkout{
		SessionID:  sessionID,
		StartedAt:  finished.Add(-30 * time.Minute),
		FinishedAt: finished,
		LocalDate:  finished.Format(time.DateOnly),
		Items:      items,
	}
}

func TestProgramProgress(t *testing.T) {
	svc, pool, user := setup(t)
	ctx := context.Background()

	p, err := svc.Progress(ctx, user, "aurum")
	if err != nil {
		t.Fatal(err)
	}
	if p.Completed != 0 || p.Total != 12 || p.Next.Position != 1 || len(p.CompletedSessionIDs) != 0 {
		t.Fatalf("sin entrenar: %+v (next %+v)", p, p.Next)
	}

	// Fuera de orden: templar la 3 no mueve la sugerida (sigue la 1), pero
	// la 3 queda con check.
	s3, _ := sessionAt(t, pool, "aurum", 3)
	if _, err := svc.RecordWorkout(ctx, user, workoutFor(s3)); err != nil {
		t.Fatal(err)
	}
	// Repetir una Fragua no suma dos checks.
	if _, err := svc.RecordWorkout(ctx, user, workoutFor(s3)); err != nil {
		t.Fatal(err)
	}
	p, err = svc.Progress(ctx, user, "aurum")
	if err != nil {
		t.Fatal(err)
	}
	if p.Completed != 1 || p.Next.Position != 1 || len(p.CompletedSessionIDs) != 1 || p.CompletedSessionIDs[0] != s3 {
		t.Errorf("después de la 3 (dos veces): completed=%d next=%+v ids=%v", p.Completed, p.Next, p.CompletedSessionIDs)
	}

	// Otra Senda en paralelo: cada una lleva su progreso.
	sp, _ := sessionAt(t, pool, "primal", 1)
	if _, err := svc.RecordWorkout(ctx, user, workoutFor(sp)); err != nil {
		t.Fatal(err)
	}
	all, err := svc.ListProgress(ctx, user)
	if err != nil {
		t.Fatal(err)
	}
	completed := map[string]int64{}
	for _, pp := range all {
		completed[pp.Program.Slug] = pp.Completed
	}
	if completed["aurum"] != 1 || completed["primal"] != 1 || completed["elite"] != 0 {
		t.Errorf("progreso por senda = %v", completed)
	}

	// Reset: Aurum queda limpia, Primal no se toca, y el historial sigue.
	if err := svc.ResetProgress(ctx, user, "aurum"); err != nil {
		t.Fatal(err)
	}
	p, _ = svc.Progress(ctx, user, "aurum")
	if p.Completed != 0 || p.ResetAt == nil || len(p.CompletedSessionIDs) != 0 {
		t.Errorf("después del reset: %+v", p)
	}
	history, _ := svc.ListWorkouts(ctx, user, 10)
	if len(history) != 3 {
		t.Errorf("el reset no debería borrar el historial: %d workouts", len(history))
	}

	if err := svc.ResetProgress(ctx, user, "no-existe"); !errors.Is(err, ErrProgramNotFound) {
		t.Errorf("reset de una senda inexistente: err = %v", err)
	}
}

func TestRecordsAndStats(t *testing.T) {
	svc, pool, user := setup(t)
	ctx := context.Background()
	s1, item := sessionAt(t, pool, "aurum", 1)

	// La primera vez no hay Mojón: no había marca que superar.
	w, err := svc.RecordWorkout(ctx, user, workoutFor(s1, ItemResult{BlockItemID: item, Reps: ptr[int16](10)}))
	if err != nil {
		t.Fatal(err)
	}
	if len(w.NewRecords) != 0 {
		t.Errorf("primera vez: new_records = %+v", w.NewRecords)
	}

	// Igualar no es Mojón; superar, sí.
	w, _ = svc.RecordWorkout(ctx, user, workoutFor(s1, ItemResult{BlockItemID: item, Reps: ptr[int16](10)}))
	if len(w.NewRecords) != 0 {
		t.Errorf("igualar: new_records = %+v", w.NewRecords)
	}
	w, _ = svc.RecordWorkout(ctx, user, workoutFor(s1, ItemResult{BlockItemID: item, Reps: ptr[int16](13)}))
	if len(w.NewRecords) != 1 || w.NewRecords[0].Value != 13 || w.NewRecords[0].Previous != 10 {
		t.Errorf("superar: new_records = %+v", w.NewRecords)
	}

	records, err := svc.Records(ctx, user)
	if err != nil {
		t.Fatal(err)
	}
	if len(records) != 1 || records[0].Value != 13 || records[0].Metric != "reps" {
		t.Errorf("mojones = %+v", records)
	}

	// Tres Fraguas hoy: la Brasa cuenta un día (cuenta días, no Fraguas).
	// Ojo: time.Now().Truncate(24*time.Hour) NO sirve para "hoy". Trunca a
	// la medianoche UTC, que en Córdoba (UTC-3) es el día anterior a las
	// 21:00. "Hoy" es el día local, como lo ve el teléfono.
	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	stats, err := svc.Stats(ctx, user, today)
	if err != nil {
		t.Fatal(err)
	}
	if stats.TotalWorkouts != 3 || stats.Brasa.Days != 1 {
		t.Errorf("stats = %+v", stats)
	}
}

func TestRecordWorkoutValidatesItems(t *testing.T) {
	svc, pool, user := setup(t)
	ctx := context.Background()

	s1, _ := sessionAt(t, pool, "aurum", 1)
	_, otherItem := sessionAt(t, pool, "aurum", 2)

	// Un ítem de otra sesión no se acepta, y como todo va en una
	// transacción, no queda ningún workout a medias.
	_, err := svc.RecordWorkout(ctx, user, workoutFor(s1, ItemResult{BlockItemID: otherItem, Reps: ptr[int16](5)}))
	var verr *ValidationError
	if !errors.As(err, &verr) {
		t.Fatalf("err = %v, want *ValidationError", err)
	}
	var n int
	pool.QueryRow(ctx, `select count(*) from workout where user_id = $1`, user).Scan(&n)
	if n != 0 {
		t.Errorf("quedaron %d workouts: la transacción no se deshizo", n)
	}

	if _, err := svc.RecordWorkout(ctx, user, workoutFor(999999)); !errors.As(err, &verr) {
		t.Errorf("sesión inexistente: err = %v, want *ValidationError", err)
	}
}

func TestWorkoutsAreIsolatedPerUser(t *testing.T) {
	svc, pool, alice := setup(t)
	_, _, bob := setup(t)
	ctx := context.Background()

	s1, _ := sessionAt(t, pool, "unbreakable", 1)
	if _, err := svc.RecordWorkout(ctx, alice, workoutFor(s1)); err != nil {
		t.Fatal(err)
	}
	got, err := svc.ListWorkouts(ctx, alice, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Program == nil || got[0].Program.Slug != "unbreakable" || got[0].DurationS != 30*60 {
		t.Errorf("historial de alice = %+v", got)
	}

	bobs, err := svc.ListWorkouts(ctx, bob, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(bobs) != 0 {
		t.Errorf("bob ve %d workouts de otro usuario", len(bobs))
	}
	bobProgress, _ := svc.Progress(ctx, bob, "unbreakable")
	if bobProgress.Completed != 0 {
		t.Errorf("bob ve el progreso de alice: %+v", bobProgress)
	}
}
