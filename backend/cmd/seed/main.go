// Command seed importa los programas de Mammoth Hunters (nivel A de
// docs/source) al modelo de la app.
//
//	go run ./cmd/seed names   # crea o completa el CSV de nombres para revisar
//	go run ./cmd/seed sql     # genera el seed SQL a partir del CSV curado
//	go run ./cmd/seed phases  # genera el SQL del calentamiento y la movilidad
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

	"github.com/santinuin/naguan-app/backend/internal/mhimport"
)

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
	outPath := flag.String("out", "../supabase/seed.sql", "archivo SQL a generar (sql)")
	phasesOut := flag.String("phases-out", "../supabase/seed_phases.sql", "archivo SQL a generar (phases)")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "uso: seed [flags] names|sql|phases\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	var err error
	switch flag.Arg(0) {
	case "names":
		err = runNames(*source, *namesPath)
	case "sql":
		err = runSQL(*source, *namesPath, *outPath)
	case "phases":
		err = runPhases(*source, *namesPath, *phasesOut)
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
	return mhimport.BuildCatalog(index, names)
}

func runSQL(source, namesPath, outPath string) error {
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
		prog := &mhimport.Program{ID: int64(i + 1), Slug: p.slug, Name: p.name}
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

// phasesSource es la transcripción del calentamiento y la movilidad de
// Unbreakable (de capturas de la app original; ver mhimport/phases.go).
const phasesSource = "Programas/Unbreakable/calentamiento_y_movilidad.txt"

// runPhases genera el SQL que agrega el calentamiento y la movilidad a
// Unbreakable. Va aparte de seed.sql porque se aplica también sobre la base
// de producción, que ya tiene el programa cargado y Fraguas templadas.
func runPhases(source, namesPath, outPath string) error {
	cat, _, err := buildCatalog(source, namesPath)
	if err != nil {
		return err
	}
	plan, err := mhimport.ReadPhasePlan(filepath.Join(source, phasesSource))
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
	if err := errors.Join(mhimport.RenderPhasesSQL(f, "unbreakable", sessions), f.Close()); err != nil {
		return err
	}
	var nBlocks int
	for _, s := range sessions {
		nBlocks += len(s.Warmup) + len(s.Mobility)
	}
	fmt.Printf("%s: %d sesiones, %d bloques de calentamiento y movilidad\n", outPath, len(sessions), nBlocks)
	return nil
}
