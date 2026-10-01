package mhimport

import (
	"regexp"
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// Side es el lado de un ejercicio unilateral. El valor vacío significa
// "sin lado" (ejercicio bilateral, o unilateral sin lado especificado).
type Side string

const (
	SideNone  Side = ""
	SideLeft  Side = "left"
	SideRight Side = "right"
)

// sideSuffix reconoce el lado al final del nombre, en las formas que usa el
// índice: "(derecha)", "(I)", "c/ bastón D", "con kettlebell izquierdo"...
// Una letra suelta cuenta solo en mayúscula: "Flow d" es la variante D.
var sideSuffix = regexp.MustCompile(
	`\s*(?:\(\s*((?i:derecha|izquierda|der|izq|dcha|izda|d|i))\s*\)` +
		`|\s((?i:derecha|izquierda|derecho|izquierdo|der|izq|dcha|izda))` +
		`|\s([DI]))\s*$`)

// SplitSide separa el lado del nombre: "Plancha lateral (derecha)" devuelve
// ("Plancha lateral", SideRight).
func SplitSide(name string) (string, Side) {
	m := sideSuffix.FindStringSubmatchIndex(name)
	if m == nil {
		return name, SideNone
	}
	// Grupos: 1 entre paréntesis, 2 palabra suelta, 3 letra suelta.
	word := ""
	for g := 1; g <= 3; g++ {
		if start := m[2*g]; start >= 0 {
			word = strings.ToLower(name[start:m[2*g+1]])
		}
	}
	side := SideRight
	if strings.HasPrefix(word, "i") {
		side = SideLeft
	}
	return strings.TrimSpace(name[:m[0]]), side
}

var (
	spaces      = regexp.MustCompile(`\s+`)
	withAbbrev  = regexp.MustCompile(`(?i)\bc/\s*`)
	kettlebell  = regexp.MustCompile(`\bKB\b`)
	onePierna   = regexp.MustCompile(`(?i)(^|[^a]\s)1 pierna`)
	notSlugChar = regexp.MustCompile(`[^a-z0-9]+`)
)

// NormalizeName propone el nombre limpio de un ejercicio, ya sin el lado:
// espacios colapsados, abreviaturas expandidas y mayúscula inicial. Es solo
// una propuesta: el nombre definitivo es el del CSV curado.
func NormalizeName(name string) string {
	s := spaces.ReplaceAllString(strings.TrimSpace(name), " ")
	s = withAbbrev.ReplaceAllString(s, "con ")
	s = kettlebell.ReplaceAllString(s, "kettlebell")
	s = onePierna.ReplaceAllString(s, "${1}a una pierna")
	return upperFirst(s)
}

func upperFirst(s string) string {
	for i, r := range s {
		return string(unicode.ToUpper(r)) + s[i+len(string(r)):]
	}
	return s
}

// Slug arma un identificador estable y legible: "Flexión en L" → "flexion-en-l".
func Slug(s string) string {
	// NFD separa cada letra de su tilde ("ó" → "o" + "´"); después
	// descartamos las marcas (categoría Mn) y queda el texto sin acentos.
	var b strings.Builder
	for _, r := range norm.NFD.String(strings.ToLower(s)) {
		if !unicode.Is(unicode.Mn, r) {
			b.WriteRune(r)
		}
	}
	return strings.Trim(notSlugChar.ReplaceAllString(b.String(), "-"), "-")
}
