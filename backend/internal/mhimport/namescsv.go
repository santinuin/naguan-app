package mhimport

import (
	"cmp"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"os"
	"slices"
	"strconv"
)

// NameRow asigna un ejercicio del índice original (SourceID) a un ejercicio
// del catálogo nuevo (Name) y a un lado. Las filas con el mismo Name son el
// mismo ejercicio: así se fusionan los duplicados de coach y los pares
// izquierda/derecha.
type NameRow struct {
	SourceID   int
	Coach      int
	SourceName string
	Name       string
	Side       Side
}

var namesHeader = []string{"source_id", "coach", "source_name", "name", "side"}

// ProposeNames arma el CSV de nombres. Las filas que ya estaban en existing
// se conservan tal cual (son las ediciones a mano); las nuevas reciben un
// nombre propuesto con SplitSide + NormalizeName.
func ProposeNames(index []SourceExercise, existing []NameRow) []NameRow {
	kept := make(map[int]NameRow, len(existing))
	for _, r := range existing {
		kept[r.SourceID] = r
	}
	out := make([]NameRow, 0, len(index))
	for _, e := range index {
		if e.ID == RestSourceID {
			continue // el descanso no es un ejercicio del catálogo
		}
		if r, ok := kept[e.ID]; ok {
			out = append(out, r)
			continue
		}
		base, side := SplitSide(e.Name)
		out = append(out, NameRow{
			SourceID:   e.ID,
			Coach:      e.Coach,
			SourceName: e.Name,
			Name:       NormalizeName(base),
			Side:       side,
		})
	}
	// Ordenado por nombre para revisar juntas las filas que se fusionan.
	slices.SortFunc(out, func(a, b NameRow) int {
		return cmp.Or(
			cmp.Compare(a.Name, b.Name),
			cmp.Compare(a.Side, b.Side),
			cmp.Compare(a.SourceID, b.SourceID),
		)
	})
	return out
}

// ReadNames lee el CSV curado. Si el archivo no existe devuelve nil, nil:
// es la primera corrida.
func ReadNames(path string) ([]NameRow, error) {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()

	r := csv.NewReader(f)
	r.FieldsPerRecord = len(namesHeader)
	if _, err := r.Read(); err != nil { // encabezado
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	var out []NameRow
	for {
		rec, err := r.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
		id, err1 := strconv.Atoi(rec[0])
		coach, err2 := strconv.Atoi(rec[1])
		side := Side(rec[4])
		if err := errors.Join(err1, err2); err != nil {
			return nil, fmt.Errorf("%s: fila %v: %w", path, rec, err)
		}
		if side != SideNone && side != SideLeft && side != SideRight {
			return nil, fmt.Errorf("%s: fila %v: lado inválido %q", path, rec, side)
		}
		out = append(out, NameRow{id, coach, rec[2], rec[3], side})
	}
	return out, nil
}

// WriteNames escribe el CSV completo.
func WriteNames(path string, rows []NameRow) error {
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	w := csv.NewWriter(f)
	w.Write(namesHeader)
	for _, r := range rows {
		w.Write([]string{
			strconv.Itoa(r.SourceID), strconv.Itoa(r.Coach), r.SourceName, r.Name, string(r.Side),
		})
	}
	w.Flush()
	// Errores de escritura (del csv.Writer y del cierre) en un solo lugar.
	return errors.Join(w.Error(), f.Close())
}
