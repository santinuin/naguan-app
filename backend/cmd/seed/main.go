// Command seed importa los programas de docs/source al modelo de la app: los
// de Mammoth Hunters (nivel A, desde los Excel) y los transcriptos a mano
// (planimport).
//
//	go run ./cmd/seed names   # crea o completa el CSV de nombres para revisar
//	go run ./cmd/seed sql     # genera el seed SQL a partir del CSV curado
//	go run ./cmd/seed phases  # genera el SQL del calentamiento y la movilidad de cada programa
//	go run ./cmd/seed titles  # imprime el UPDATE de los títulos de las sesiones
//	go run ./cmd/seed plans   # genera el SQL de los programas transcriptos a mano
//	go run ./cmd/seed plans efecto-kettlebell   # … solo de esos programas
//	go run ./cmd/seed plans-update desencadenado # SQL que completa lo nuevo del modelo en lo ya cargado
//	go run ./cmd/seed -tag aproximacion plans-update barra-libre-1   # … con otro nombre de archivo
//
// El CSV de nombres se versiona (solo tiene nombres); el SQL no, porque
// incluye descripciones y videos de la fuente.
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"github.com/santinuin/naguan-app/backend/internal/mhimport"
	"github.com/santinuin/naguan-app/backend/internal/planimport"
)

// programOrder es el orden de las Sendas en la app (program.position): la
// primera es la 1. Un programa que no está acá queda sin posición, al final.
// Para reordenar una base que ya existe hace falta además una migración
// (ver supabase/migrations/20261030100000_program_position.sql).
var programOrder = []string{
	"unbreakable",
	"ring-master",
	"desencadenado",
	"efecto-kettlebell",
	"barra-libre-1",
	"barra-libre-1-intermedio",
	"barra-libre-2",
	"barra-libre-3",
	"barra-libre-4",
	"pausas-activas",
	"padel",
	"futbol",
	// Los de prioridad baja, al final.
	"elite",
	"primal",
	"aurum",
}

// programPosition es la posición de un programa en programOrder (0 si no
// está).
func programPosition(slug string) int {
	return slices.Index(programOrder, slug) + 1
}

// programs son los programas del nivel A, en el orden en que se cargan.
var programs = []struct{ file, slug, name string }{
	{"Programas/Unbreakable/Unbreakable.xlsx", "unbreakable", "Unbreakable"},
	{"Programas/Ring Master.xlsx", "ring-master", "Ring Master"},
	{"Programas/Elite.xlsx", "elite", "Elite"},
	{"Programas/Primal.xlsx", "primal", "Primal"},
	{"Programas/Aurum.xlsx", "aurum", "Aurum"},
}

func main() {
	source := flag.String("source", "../docs/source", "carpeta con los Excel originales")
	namesPath := flag.String("names", "seed/exercise_names.csv", "CSV curado de nombres")
	titlesPath := flag.String("titles", "seed/session_titles.csv", "CSV de títulos de las sesiones")
	outPath := flag.String("out", "../supabase/seed.sql", "archivo SQL a generar (sql)")
	phasesDir := flag.String("phases-dir", "../supabase", "carpeta de los SQL a generar (phases y plans)")
	tag := flag.String("tag", "detalles", "plans-update: sufijo del archivo (seed_<programa>_<tag>.sql); uno nuevo por cada actualización")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "uso: seed [flags] names|sql|phases|titles|plans|plans-update [programa...]\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	var err error
	switch flag.Arg(0) {
	case "names":
		err = runNames(*source, *namesPath)
	case "sql":
		err = runSQL(*source, *namesPath, *titlesPath, *outPath)
	case "titles":
		err = runTitles(*titlesPath)
	case "phases":
		err = runPhases(*source, *namesPath, *phasesDir)
	case "plans":
		err = runPlans(*source, *namesPath, *phasesDir, flag.Args()[1:], "")
	case "plans-update":
		err = runPlans(*source, *namesPath, *phasesDir, flag.Args()[1:], *tag)
	default:
		flag.Usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func runNames(source, namesPath string) error {
	index, err := mhimport.ReadIndex(filepath.Join(source, "Indice de ejercicios.xlsx"))
	if err != nil {
		return err
	}
	existing, err := mhimport.ReadNames(namesPath)
	if err != nil {
		return err
	}
	rows := mhimport.ProposeNames(index, existing)
	if err := mhimport.WriteNames(namesPath, rows); err != nil {
		return err
	}
	fmt.Printf("%s: %d filas (%d nuevas)\n", namesPath, len(rows), len(rows)-len(existing))
	return nil
}

// buildCatalog lee el índice y el CSV de nombres y arma el catálogo: lo
// necesitan tanto sql como phases.
func buildCatalog(source, namesPath string) (*mhimport.Catalog, []string, error) {
	index, err := mhimport.ReadIndex(filepath.Join(source, "Indice de ejercicios.xlsx"))
	if err != nil {
		return nil, nil, err
	}
	names, err := mhimport.ReadNames(namesPath)
	if err != nil {
		return nil, nil, err
	}
	if names == nil {
		return nil, nil, fmt.Errorf("no existe %s: corré primero el comando names", namesPath)
	}
	cat, warns, err := mhimport.BuildCatalog(index, names)
	if err != nil {
		return nil, nil, err
	}
	loaded, err := mhimport.ReadLoaded("seed/ejercicios_con_carga.txt")
	if err != nil {
		return nil, nil, err
	}
	return cat, warns, cat.MarkLoaded(loaded)
}

func runSQL(source, namesPath, titlesPath, outPath string) error {
	cat, warns, err := buildCatalog(source, namesPath)
	if err != nil {
		return err
	}
	for _, w := range warns {
		fmt.Fprintln(os.Stderr, "aviso:", w)
	}

	// Juntamos los errores de todos los programas antes de cortar: así una
	// corrida muestra todo lo que hay que corregir, no solo lo primero.
	var progs []*mhimport.Program
	var errs []error
	var sessionID int64
	for i, p := range programs {
		srcs, err := mhimport.ReadProgram(filepath.Join(source, p.file))
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", p.name, err))
			continue
		}
		prog := &mhimport.Program{ID: int64(i + 1), Slug: p.slug, Name: p.name, Position: programPosition(p.slug)}
		for _, src := range srcs {
			s, err := mhimport.BuildSession(src, cat)
			if err != nil {
				errs = append(errs, fmt.Errorf("%s / %s: %w", p.name, src.Sheet, err))
				continue
			}
			sessionID++
			s.ID = sessionID
			prog.Sessions = append(prog.Sessions, s)
		}
		progs = append(progs, prog)
	}
	if err := errors.Join(errs...); err != nil {
		return err
	}
	titles, err := mhimport.ReadSessionTitles(titlesPath)
	if err != nil {
		return err
	}
	if err := titles.Apply(progs); err != nil {
		return err
	}

	f, err := os.Create(outPath)
	if err != nil {
		return err
	}
	if err := errors.Join(mhimport.RenderSQL(f, cat, progs), f.Close()); err != nil {
		return err
	}

	var nSessions int
	for _, p := range progs {
		nSessions += len(p.Sessions)
	}
	fmt.Printf("%s: %d ejercicios, %d progresiones, %d programas, %d sesiones\n",
		outPath, len(cat.Exercises), len(cat.Progressions), len(progs), nSessions)
	return nil
}

// phasePrograms son los programas con calentamiento y movilidad. Cada uno
// genera su propio SQL: la CLI de Supabase registra cada archivo de seed con
// su hash y aplica solo los nuevos, así que un programa nuevo no puede tocar
// el archivo de otro que ya está en producción (cambiaría su hash).
var phasePrograms = []struct {
	slug string
	plan string // plan de calentamiento y movilidad
	out  string // SQL a generar, dentro de -phases-dir
}{
	// Transcripción de capturas de la app original (no versionada: vive en
	// docs/source, con el resto del material de la fuente).
	{"unbreakable", "{source}/Programas/Unbreakable/calentamiento_y_movilidad.txt", "seed_phases.sql"},
	// Reconstrucción propia (la app original los perdió al cerrar): se versiona.
	{"ring-master", "seed/ring_master_fases.txt", "seed_phases_ring_master.sql"},
}

// runPhases genera el SQL que agrega el calentamiento y la movilidad a cada
// programa de phasePrograms. Va aparte de seed.sql porque se aplica también
// sobre la base de producción, que ya tiene los programas cargados y Fraguas
// templadas.
func runPhases(source, namesPath, outDir string) error {
	cat, _, err := buildCatalog(source, namesPath)
	if err != nil {
		return err
	}
	var errs []error
	for _, p := range phasePrograms {
		planPath := strings.Replace(p.plan, "{source}", source, 1)
		if err := writePhases(cat, p.slug, planPath, filepath.Join(outDir, p.out)); err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", p.slug, err))
		}
	}
	return errors.Join(errs...)
}

func writePhases(cat *mhimport.Catalog, slug, planPath, outPath string) error {
	plan, err := mhimport.ReadPhasePlan(planPath)
	if err != nil {
		return err
	}
	sessions, err := mhimport.BuildPhases(plan, cat)
	if err != nil {
		return err
	}

	f, err := os.Create(outPath)
	if err != nil {
		return err
	}
	if err := errors.Join(mhimport.RenderPhasesSQL(f, slug, sessions), f.Close()); err != nil {
		return err
	}
	var nBlocks int
	for _, s := range sessions {
		nBlocks += len(s.Warmup) + len(s.Mobility)
	}
	fmt.Printf("%s: %d sesiones, %d bloques de calentamiento y movilidad\n", outPath, len(sessions), nBlocks)
	return nil
}

// runTitles imprime el UPDATE de los títulos de las sesiones, para pegar en
// el editor SQL de Supabase (producción). No es un archivo de seed: la CLI
// no vuelve a correr un seed que ya aplicó, y los títulos se corrigen.
func runTitles(titlesPath string) error {
	titles, err := mhimport.ReadSessionTitles(titlesPath)
	if err != nil {
		return err
	}
	return mhimport.RenderTitlesSQL(os.Stdout, titles)
}

// plans son los programas transcriptos a mano (ver internal/planimport). La
// transcripción es contenido de la fuente y vive en docs/source (no se
// versiona); los ejercicios nuevos y las progresiones tienen texto propio y
// se versionan. Como en phasePrograms, cada programa genera su propio SQL.
type planSource struct {
	slug, name string
	plan       string // transcripción
	extras     string // ejercicios nuevos y progresiones
	out        string // SQL a generar, dentro de -phases-dir
}

var plans = []planSource{
	{
		"desencadenado", "Desencadenado",
		"{source}/Programas/Desencadenado /desencadenado.txt",
		"seed/desencadenado_catalogo.txt",
		"seed_desencadenado.sql",
	},
	{
		"efecto-kettlebell", "Efecto Kettlebell",
		"{source}/Programas/Efecto Kettlebell/efecto_kettlebell.txt",
		"seed/efecto_kettlebell_catalogo.txt",
		"seed_efecto_kettlebell.sql",
	},
	// Barra Libre: una Senda por fase (más la Fase I para intermedios), con
	// un catálogo propio compartido. Usa ejercicios de Efecto Kettlebell
	// (sus HIIT), así que sus seeds van después.
	{
		"barra-libre-1", "Barra Libre I: Fuerza",
		"{source}/Programas/Barra Libre/barra_libre_1.txt",
		"seed/barra_libre_catalogo.txt",
		"seed_barra_libre_1.sql",
	},
	{
		"barra-libre-1-intermedio", "Barra Libre I: Fuerza (intermedio)",
		"{source}/Programas/Barra Libre/barra_libre_1_intermedio.txt",
		"seed/barra_libre_catalogo.txt",
		"seed_barra_libre_1_intermedio.sql",
	},
	{
		"barra-libre-2", "Barra Libre II: Hipertrofia",
		"{source}/Programas/Barra Libre/barra_libre_2.txt",
		"seed/barra_libre_catalogo.txt",
		"seed_barra_libre_2.sql",
	},
	{
		"barra-libre-3", "Barra Libre III: Definición máxima",
		"{source}/Programas/Barra Libre/barra_libre_3.txt",
		"seed/barra_libre_catalogo.txt",
		"seed_barra_libre_3.sql",
	},
	{
		"barra-libre-4", "Barra Libre IV: Ajustes",
		"{source}/Programas/Barra Libre/barra_libre_4.txt",
		"seed/barra_libre_catalogo.txt",
		"seed_barra_libre_4.sql",
	},
	// Movilidad: pausas activas y antes y después de un deporte. No son de
	// un libro sino propias, así que la "transcripción" también se versiona
	// (en seed/, sin {source}). Comparten un catálogo.
	{
		"pausas-activas", "Pausas activas",
		"seed/pausas_activas.txt",
		"seed/movilidad_catalogo.txt",
		"seed_pausas_activas.sql",
	},
	{
		"padel", "Pádel",
		"seed/padel.txt",
		"seed/movilidad_catalogo.txt",
		"seed_padel.sql",
	},
	{
		"futbol", "Fútbol",
		"seed/futbol.txt",
		"seed/movilidad_catalogo.txt",
		"seed_futbol.sql",
	},
}

// runPlans genera el SQL de cada programa de plans, o solo de los que se
// nombran (por slug). Va aparte de seed.sql por lo mismo que las fases: se
// aplica también sobre la base de producción, que ya tiene el catálogo y
// Fraguas templadas.
//
// Nombrar los programas importa cuando otro ya está en producción: la CLI de
// Supabase reconoce cada seed por su hash, y regenerar un archivo ya
// aplicado (por un cambio en el importador, aunque dé los mismos datos) le
// cambia el hash sin que haga falta.
//
// Con un updateTag, en vez del seed que crea el programa escribe el que
// completa los detalles en uno ya cargado (planimport.RenderUpdateSQL), en
// seed_<programa>_<updateTag>.sql. Cada actualización necesita un tag nuevo:
// la CLI de Supabase no vuelve a correr un seed que ya aplicó.
func runPlans(source, namesPath, outDir string, only []string, updateTag string) error {
	update := updateTag != ""
	selected := plans
	if len(only) > 0 {
		selected = nil
		var unknown []string
		for _, slug := range only {
			i := slices.IndexFunc(plans, func(p planSource) bool { return p.slug == slug })
			if i < 0 {
				unknown = append(unknown, slug)
				continue
			}
			selected = append(selected, plans[i])
		}
		if len(unknown) > 0 {
			var known []string
			for _, p := range plans {
				known = append(known, p.slug)
			}
			return fmt.Errorf("programas desconocidos: %s (hay: %s)",
				strings.Join(unknown, ", "), strings.Join(known, ", "))
		}
	}

	cat, _, err := buildCatalog(source, namesPath)
	if err != nil {
		return err
	}
	// Los ejercicios nuevos de cada plan, por archivo: varios programas
	// pueden compartir uno (las fases de Barra Libre), y cada plan puede usar
	// los de los demás (ver planimport.Build).
	extras := map[string]*planimport.CatalogExtras{}
	for _, p := range plans {
		if _, ok := extras[p.extras]; ok {
			continue
		}
		ex, err := planimport.ReadCatalogExtras(p.extras)
		if err != nil {
			return fmt.Errorf("%s: %w", p.extras, err)
		}
		extras[p.extras] = ex
	}
	var errs []error
	for _, p := range selected {
		var others []*planimport.CatalogExtras
		for path, ex := range extras {
			if path != p.extras {
				others = append(others, ex)
			}
		}
		out := p.out
		if update {
			out = strings.TrimSuffix(out, ".sql") + "_" + updateTag + ".sql"
		}
		if err := writePlan(cat, p, strings.Replace(p.plan, "{source}", source, 1),
			extras[p.extras], others, filepath.Join(outDir, out), update); err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", p.slug, err))
		}
	}
	return errors.Join(errs...)
}

func writePlan(cat *mhimport.Catalog, p planSource, planPath string, extras *planimport.CatalogExtras,
	others []*planimport.CatalogExtras, outPath string, update bool) error {
	plan, err := planimport.ReadPlan(planPath)
	if err != nil {
		return err
	}
	prog, err := planimport.Build(p.slug, p.name, plan, extras, cat, others...)
	if err != nil {
		return err
	}
	prog.Position = programPosition(p.slug)

	f, err := os.Create(outPath)
	if err != nil {
		return err
	}
	render := planimport.RenderSQL
	if update {
		render = planimport.RenderUpdateSQL
	}
	if err := errors.Join(render(f, prog), f.Close()); err != nil {
		return err
	}
	fmt.Printf("%s: %s\n", outPath, prog)
	return nil
}
