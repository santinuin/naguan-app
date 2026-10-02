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
	if _, _, err := svc.RecordWorkout(ctx, user, workoutFor(s3)); err != nil {
		t.Fatal(err)
	}
	// Repetir una Fragua no suma dos checks.
	if _, _, err := svc.RecordWorkout(ctx, user, workoutFor(s3)); err != nil {
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
	if _, _, err := svc.RecordWorkout(ctx, user, workoutFor(sp)); err != nil {
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
	history, _ := svc.ListWorkouts(ctx, user, 10, 0)
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
	w, _, err := svc.RecordWorkout(ctx, user, workoutFor(s1, ItemResult{BlockItemID: item, Reps: ptr[int16](10)}))
	if err != nil {
		t.Fatal(err)
	}
	if len(w.NewRecords) != 0 {
		t.Errorf("primera vez: new_records = %+v", w.NewRecords)
	}

	// Igualar no es Mojón; superar, sí.
	w, _, _ = svc.RecordWorkout(ctx, user, workoutFor(s1, ItemResult{BlockItemID: item, Reps: ptr[int16](10)}))
	if len(w.NewRecords) != 0 {
		t.Errorf("igualar: new_records = %+v", w.NewRecords)
	}
	w, _, _ = svc.RecordWorkout(ctx, user, workoutFor(s1, ItemResult{BlockItemID: item, Reps: ptr[int16](13)}))
	if len(w.NewRecords) != 1 || w.NewRecords[0].Value != 13 || w.NewRecords[0].Previous != 10 {
		t.Errorf("superar: new_records = %+v", w.NewRecords)
	}

	records, err := svc.Records(ctx, user)
	if err != nil {
		t.Fatal(err)
	}
	if len(records) != 1 || records[0].Value != 13 || records[0].Metric != "reps" {
		t.Fatalf("mojones = %+v", records)
	}
	// El slug (para abrir el ejercicio) y el día en que se logró.
	if records[0].ExerciseSlug == "" || records[0].AchievedOn != workoutFor(s1).LocalDate {
		t.Errorf("mojón sin slug o con otra fecha: %+v", records[0])
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

func TestListWorkoutsPages(t *testing.T) {
	svc, pool, user := setup(t)
	ctx := context.Background()
	s1, _ := sessionAt(t, pool, "aurum", 1)

	// Cinco Fraguas que terminan en el MISMO instante (workoutFor usa la
	// misma hora): solo el id las ordena, y ninguna tiene que repetirse ni
	// perderse entre páginas.
	want := map[int64]bool{}
	for range 5 {
		w, _, err := svc.RecordWorkout(ctx, user, workoutFor(s1))
		if err != nil {
			t.Fatal(err)
		}
		want[w.ID] = true
	}

	var got []int64
	var before int64
	for page := 0; ; page++ {
		ws, err := svc.ListWorkouts(ctx, user, 2, before)
		if err != nil {
			t.Fatal(err)
		}
		if len(ws) == 0 {
			break
		}
		if page > 3 {
			t.Fatal("la paginación no termina")
		}
		for _, w := range ws {
			got = append(got, w.ID)
		}
		before = ws[len(ws)-1].ID
	}
	if len(got) != 5 {
		t.Fatalf("ids paginados = %v, want 5 distintos", got)
	}
	for i, id := range got {
		if !want[id] {
			t.Errorf("id %d repetido o ajeno", id)
		}
		delete(want, id)
		// Mismo finished_at: más reciente = id más alto.
		if i > 0 && id > got[i-1] {
			t.Errorf("orden: %v", got)
		}
	}

	// Un cursor que no es del usuario no trae nada (no filtra datos ajenos).
	if ws, _ := svc.ListWorkouts(ctx, user, 2, 1<<62); len(ws) != 0 {
		t.Errorf("cursor inexistente: %d workouts", len(ws))
	}
}

func TestRecordWorkoutWithSwappedExercise(t *testing.T) {
	svc, pool, user := setup(t)
	ctx := context.Background()
	s1, item := sessionAt(t, pool, "aurum", 1)

	// Otro ejercicio cualquiera, distinto del que indica el bloque.
	var other, original string
	err := pool.QueryRow(ctx, `
		select e.slug, o.slug
		from block_item bi
		join exercise o on o.id = bi.exercise_id
		join exercise e on e.id <> bi.exercise_id
		where bi.id = $1
		order by e.id limit 1`, item).Scan(&other, &original)
	if err != nil {
		t.Fatal(err)
	}

	// Dos veces el ejercicio cambiado: la segunda supera a la primera, y el
	// Mojón tiene que ser del ejercicio hecho, no del bloque.
	for _, reps := range []int16{5, 8} {
		w, _, err := svc.RecordWorkout(ctx, user, workoutFor(s1,
			ItemResult{BlockItemID: item, ExerciseSlug: &other, Reps: ptr(reps)}))
		if err != nil {
			t.Fatal(err)
		}
		if reps == 8 && (len(w.NewRecords) != 1 || w.NewRecords[0].ExerciseSlug != other) {
			t.Errorf("mojón del cambiado: %+v", w.NewRecords)
		}
	}
	// El ejercicio original no tiene marca: hacerlo ahora es la primera vez.
	w, _, err := svc.RecordWorkout(ctx, user, workoutFor(s1, ItemResult{BlockItemID: item, Reps: ptr[int16](20)}))
	if err != nil {
		t.Fatal(err)
	}
	if len(w.NewRecords) != 0 {
		t.Errorf("el original heredó la marca del cambiado: %+v", w.NewRecords)
	}

	records, _ := svc.Records(ctx, user)
	got := map[string]int32{}
	for _, r := range records {
		got[r.ExerciseSlug] = r.Value
	}
	if got[other] != 8 || got[original] != 20 {
		t.Errorf("mojones por ejercicio = %v", got)
	}

	missing := "no-existe"
	_, _, err = svc.RecordWorkout(ctx, user, workoutFor(s1,
		ItemResult{BlockItemID: item, ExerciseSlug: &missing, Reps: ptr[int16](1)}))
	var verr *ValidationError
	if !errors.As(err, &verr) {
		t.Errorf("slug inexistente: err = %v, want ValidationError", err)
	}
}

func TestRecordWorkoutValidatesItems(t *testing.T) {
	svc, pool, user := setup(t)
	ctx := context.Background()

	s1, _ := sessionAt(t, pool, "aurum", 1)
	_, otherItem := sessionAt(t, pool, "aurum", 2)

	// Un ítem de otra sesión no se acepta, y como todo va en una
	// transacción, no queda ningún workout a medias.
	_, _, err := svc.RecordWorkout(ctx, user, workoutFor(s1, ItemResult{BlockItemID: otherItem, Reps: ptr[int16](5)}))
	var verr *ValidationError
	if !errors.As(err, &verr) {
		t.Fatalf("err = %v, want *ValidationError", err)
	}
	var n int
	pool.QueryRow(ctx, `select count(*) from workout where user_id = $1`, user).Scan(&n)
	if n != 0 {
		t.Errorf("quedaron %d workouts: la transacción no se deshizo", n)
	}

	if _, _, err := svc.RecordWorkout(ctx, user, workoutFor(999999)); !errors.As(err, &verr) {
		t.Errorf("sesión inexistente: err = %v, want *ValidationError", err)
	}
}

func TestWorkoutsAreIsolatedPerUser(t *testing.T) {
	svc, pool, alice := setup(t)
	_, _, bob := setup(t)
	ctx := context.Background()

	s1, _ := sessionAt(t, pool, "unbreakable", 1)
	if _, _, err := svc.RecordWorkout(ctx, alice, workoutFor(s1)); err != nil {
		t.Fatal(err)
	}
	got, err := svc.ListWorkouts(ctx, alice, 10, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Program == nil || got[0].Program.Slug != "unbreakable" || got[0].DurationS != 30*60 {
		t.Errorf("historial de alice = %+v", got)
	}

	bobs, err := svc.ListWorkouts(ctx, bob, 10, 0)
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

func TestDeletedUserIsUnknown(t *testing.T) {
	svc, pool, user := setup(t)
	ctx := context.Background()
	s1, _ := sessionAt(t, pool, "aurum", 1)

	// Se borra la cuenta: el token seguiría siendo válido hasta vencer.
	if _, err := pool.Exec(ctx, `delete from auth.users where id = $1`, user); err != nil {
		t.Fatal(err)
	}

	if _, _, err := svc.RecordWorkout(ctx, user, workoutFor(s1)); !errors.Is(err, ErrUnknownUser) {
		t.Errorf("registrar con un usuario borrado: err = %v, want ErrUnknownUser", err)
	}
	if err := svc.ResetProgress(ctx, user, "aurum"); !errors.Is(err, ErrUnknownUser) {
		t.Errorf("resetear con un usuario borrado: err = %v, want ErrUnknownUser", err)
	}
}

func TestRecordWorkoutIsIdempotent(t *testing.T) {
	svc, pool, user := setup(t)
	ctx := context.Background()
	s1, item := sessionAt(t, pool, "aurum", 1)

	clientID := newUUID()
	w := workoutFor(s1, ItemResult{BlockItemID: item, Reps: ptr[int16](10)})
	w.ClientID = &clientID

	first, created, err := svc.RecordWorkout(ctx, user, w)
	if err != nil || !created {
		t.Fatalf("primer registro: created=%v err=%v", created, err)
	}
	// El reintento (sin señal la primera vez, o se perdió la respuesta):
	// mismo client_id, mismo workout, nada duplicado.
	again, created, err := svc.RecordWorkout(ctx, user, w)
	if err != nil || created || again.ID != first.ID {
		t.Fatalf("reintento: created=%v id=%d (want %d) err=%v", created, again.ID, first.ID, err)
	}
	var n int
	pool.QueryRow(ctx, `select count(*) from workout where user_id = $1`, user).Scan(&n)
	if n != 1 {
		t.Errorf("workouts = %d, want 1", n)
	}
}

func TestRecordWorkoutAmrapRounds(t *testing.T) {
	svc, pool, user := setup(t)
	ctx := context.Background()

	// Una sesión con un bloque AMRAP (los hay en Unbreakable y Ring Master).
	var sessionID int64
	var position int16
	err := pool.QueryRow(ctx, `select session_id, position from block where type = 'amrap' limit 1`).
		Scan(&sessionID, &position)
	if err != nil {
		t.Fatal(err)
	}

	w := workoutFor(sessionID)
	w.Amraps = []AmrapResult{{BlockPosition: position, Rounds: 7}}
	saved, _, err := svc.RecordWorkout(ctx, user, w)
	if err != nil {
		t.Fatal(err)
	}
	var rounds int16
	pool.QueryRow(ctx, `select rounds from workout_amrap where workout_id = $1`, saved.ID).Scan(&rounds)
	if rounds != 7 {
		t.Errorf("vueltas guardadas = %d, want 7", rounds)
	}

	// Un bloque que no es AMRAP se rechaza.
	w.Amraps = []AmrapResult{{BlockPosition: 99, Rounds: 1}}
	var verr *ValidationError
	if _, _, err := svc.RecordWorkout(ctx, user, w); !errors.As(err, &verr) {
		t.Errorf("bloque inválido: err = %v, want *ValidationError", err)
	}
}
