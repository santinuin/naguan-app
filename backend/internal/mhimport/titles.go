package mhimport

import (
	"bufio"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"slices"
	"strconv"
	"strings"
)

// SessionTitles son los nombres propios de las sesiones, por programa y
// posición: pisan el título que sale de la fuente ("Sesión 8" pasa a
// "Metabólica 3"). Vienen de seed/session_titles.csv, que se versiona (solo
// tiene nombres) y se edita a mano.
type SessionTitles map[string]map[int]string

var titlesHeader = []string{"program", "position", "title"}

// ReadSessionTitles lee el CSV. Si no existe, devuelve un mapa vacío: los
// títulos son opcionales.
func ReadSessionTitles(path string) (SessionTitles, error) {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return SessionTitles{}, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return parseSessionTitles(f)
}

func parseSessionTitles(r io.Reader) (SessionTitles, error) {
	records, err := csv.NewReader(r).ReadAll()
	if err != nil {
		return nil, err
	}
	if len(records) == 0 || !slices.Equal(records[0], titlesHeader) {
		return nil, fmt.Errorf("el encabezado tiene que ser %v", titlesHeader)
	}
	out := SessionTitles{}
	var errs []error
	for i, rec := range records[1:] {
		line := i + 2
		pos, err := strconv.Atoi(rec[1])
		title := strings.TrimSpace(rec[2])
		switch {
		case err != nil || pos <= 0:
			errs = append(errs, fmt.Errorf("línea %d: posición inválida %q", line, rec[1]))
		case title == "":
			errs = append(errs, fmt.Errorf("línea %d: título vacío", line))
		case out[rec[0]][pos] != "":
			errs = append(errs, fmt.Errorf("línea %d: %s %d repetida", line, rec[0], pos))
		default:
			if out[rec[0]] == nil {
				out[rec[0]] = map[int]string{}
			}
			out[rec[0]][pos] = title
		}
	}
	return out, errors.Join(errs...)
}

// Apply pone los títulos en las sesiones de los programas. Un título para
// un programa o una posición que no existe es un error (probablemente un
// error de tipeo en el CSV).
func (t SessionTitles) Apply(programs []*Program) error {
	bySlug := map[string]*Program{}
	for _, p := range programs {
		bySlug[p.Slug] = p
	}
	var errs []error
	for _, slug := range slices.Sorted(maps.Keys(t)) {
		p, ok := bySlug[slug]
		if !ok {
			errs = append(errs, fmt.Errorf("títulos: no existe el programa %q", slug))
			continue
		}
		for pos, title := range t[slug] {
			if pos > len(p.Sessions) {
				errs = append(errs, fmt.Errorf("títulos: %s no tiene sesión %d", slug, pos))
				continue
			}
			p.Sessions[pos-1].Title = title
		}
	}
	return errors.Join(errs...)
}

// RenderTitlesSQL escribe un UPDATE que pone los títulos sobre una base que
// ya tiene los programas (la de producción). Busca cada sesión por programa
// y posición, y se puede correr las veces que haga falta: pone los mismos
// valores.
func RenderTitlesSQL(out io.Writer, t SessionTitles) error {
	w := &sqlWriter{w: bufio.NewWriter(out)}
	w.printf("-- Generado por backend/cmd/seed (comando titles) desde seed/session_titles.csv.\n")
	w.printf("update session s set title = v.title\nfrom (values\n")
	var rows []string
	for _, slug := range slices.Sorted(maps.Keys(t)) {
		for _, pos := range slices.Sorted(maps.Keys(t[slug])) {
			rows = append(rows, fmt.Sprintf("  (%s, %d, %s)", str(slug), pos, str(t[slug][pos])))
		}
	}
	w.printf("%s\n) as v(program, position, title)\n", strings.Join(rows, ",\n"))
	w.printf("join program p on p.slug = v.program\n")
	w.printf("join program_session ps on ps.program_id = p.id and ps.position = v.position\n")
	w.printf("where s.id = ps.session_id;\n")
	return w.flush()
}
