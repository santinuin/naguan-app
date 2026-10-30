package mhimport

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strings"
)

// Los ejercicios del índice que se hacen con carga (barra, kettlebell,
// mancuerna): la app pide el peso. El índice original no lo dice, así que va
// en una lista curada a mano (backend/seed/ejercicios_con_carga.txt), un
// nombre del catálogo por línea, con comentarios "#".

// ReadLoaded lee la lista de ejercicios con carga.
func ReadLoaded(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var names []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		names = append(names, line)
	}
	return names, sc.Err()
}

// MarkLoaded marca como "con carga" los ejercicios de la lista. Un nombre
// que no está en el catálogo es un error: la lista se escribe a mano.
func (c *Catalog) MarkLoaded(names []string) error {
	bySlug := make(map[string]*Exercise, len(c.Exercises))
	for _, e := range c.Exercises {
		bySlug[e.Slug] = e
	}
	var errs []error
	for _, name := range names {
		e, ok := bySlug[Slug(name)]
		if !ok {
			errs = append(errs, fmt.Errorf("ejercicios con carga: %q no está en el catálogo", name))
			continue
		}
		e.Loaded = true
	}
	return errors.Join(errs...)
}
