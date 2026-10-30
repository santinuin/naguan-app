package planimport

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/santinuin/naguan-app/backend/internal/mhimport"
)

// Lo que un plan suma al catálogo: ejercicios que el índice de Mammoth
// Hunters no tiene y cadenas de progresión (los niveles del libro). Va en un
// archivo aparte, versionado, porque el texto es propio:
//
//	+ Elevación de talones | 3            ← nombre y MET
//	Apoyá la punta de los pies en un escalón…   ← descripción (Markdown),
//	hasta la próxima línea en blanco
//
//	+ Flexión a una mano | 4 | unilateral
//	…
//
//	+ Swing | 9 | carga                  ← se hace con carga: la app pide el peso
//	…
//
//	progresión: Flexión inclinada > Flexión con rodillas > Flexión

// CatalogExtras es el archivo leído.
type CatalogExtras struct {
	Exercises []mhimport.NewExercise
	// Unilateral y Loaded (con carga), por slug, de los ejercicios nuevos
	// (NewExercise no los tiene: los de mhimport son bilaterales y sin carga).
	Unilateral map[string]bool
	Loaded     map[string]bool
	// Cadenas de nombres, de la más fácil a la más difícil.
	Chains [][]string
}

var (
	newExerciseLine = regexp.MustCompile(`^\+\s*(.+?)\s*\|\s*(\d+(?:\.\d+)?)\s*((?:\|\s*(?:unilateral|carga)\s*)*)$`)
	chainLine       = regexp.MustCompile(`^progresión:\s*(.+)$`)
)

// ReadCatalogExtras lee el archivo de ejercicios nuevos y progresiones.
func ReadCatalogExtras(path string) (*CatalogExtras, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return parseCatalogExtras(f)
}

func parseCatalogExtras(r io.Reader) (*CatalogExtras, error) {
	ex := &CatalogExtras{Unilateral: map[string]bool{}, Loaded: map[string]bool{}}
	var errs []error
	var current *mhimport.NewExercise // ejercicio cuya descripción se lee
	var desc []string
	closeExercise := func() {
		if current != nil {
			current.Description = strings.Join(desc, "\n")
			ex.Exercises = append(ex.Exercises, *current)
		}
		current, desc = nil, nil
	}

	sc := bufio.NewScanner(r)
	for line := 1; sc.Scan(); line++ {
		text := strings.TrimSpace(sc.Text())
		fail := func(format string, args ...any) {
			errs = append(errs, fmt.Errorf("línea %d: "+format, append([]any{line}, args...)...))
		}
		switch {
		case text == "":
			closeExercise()
		case current != nil:
			desc = append(desc, text)
		case strings.HasPrefix(text, "#"):
			continue
		case newExerciseLine.MatchString(text):
			m := newExerciseLine.FindStringSubmatch(text)
			met, _ := strconv.ParseFloat(m[2], 64)
			current = &mhimport.NewExercise{Slug: mhimport.Slug(m[1]), Name: m[1], MET: met}
			ex.Unilateral[current.Slug] = strings.Contains(m[3], "unilateral")
			ex.Loaded[current.Slug] = strings.Contains(m[3], "carga")
		case chainLine.MatchString(text):
			var chain []string
			for name := range strings.SplitSeq(chainLine.FindStringSubmatch(text)[1], ">") {
				chain = append(chain, strings.TrimSpace(name))
			}
			if len(chain) < 2 {
				fail("una progresión necesita al menos dos ejercicios")
			}
			ex.Chains = append(ex.Chains, chain)
		default:
			fail("no se entiende %q", text)
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	closeExercise()
	for _, e := range ex.Exercises {
		if e.Description == "" {
			errs = append(errs, fmt.Errorf("%q no tiene descripción", e.Name))
		}
	}
	return ex, errors.Join(errs...)
}
