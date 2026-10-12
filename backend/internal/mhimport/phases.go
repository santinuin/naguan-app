package mhimport

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"maps"
	"os"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

// Calentamiento y movilidad de un programa (hoy, Unbreakable). La fuente no
// es un Excel sino una transcripción a mano de las capturas de la app
// original (docs/source/Programas/Unbreakable/calentamiento_y_movilidad.txt):
// plantillas de ejercicios y, al final, qué plantilla usa cada sesión.
//
//	@CAL01
//	Saltar a la cuerda | 60s
//	Hollow hold | 20s | x2      ← ese ejercicio, 2 vueltas
//	x2:                         ← un grupo que se repite 2 vueltas
//	Flexión escapular | 10r
//	Dominada escapular | 10r
//	end
//
//	# Sesiones
//	1: CAL01 MOV01

// Phase es la parte de una sesión a la que pertenece un bloque (el enum
// block_phase de la base).
type Phase string

const (
	PhaseWarmup   Phase = "warmup"
	PhaseMobility Phase = "mobility"
)

// PhaseItem es un ejercicio de una plantilla, tal como está escrito.
type PhaseItem struct {
	Name      string
	DurationS int
	Reps      int
}

// PhaseGroup son ejercicios que se hacen juntos Rounds vueltas. Los
// ejercicios sin vueltas marcadas se agrupan de a varios con Rounds = 1.
type PhaseGroup struct {
	Rounds int
	Items  []PhaseItem
}

// PhasePlan es la transcripción leída: las plantillas por nombre y, por
// número de sesión, sus dos plantillas (calentamiento y movilidad).
type PhasePlan struct {
	Templates map[string][]PhaseGroup
	Sessions  map[int][2]string
}

var (
	phaseItemLine    = regexp.MustCompile(`^(.+?)\s*\|\s*(\d+)([sr])\s*(?:\|\s*x(\d+)\s*)?$`)
	phaseGroupLine   = regexp.MustCompile(`^x(\d+):$`)
	phaseSessionLine = regexp.MustCompile(`^(\d+):\s*(\S+)\s+(\S+)$`)
)

// ReadPhasePlan lee la transcripción. Corta con error ante cualquier línea
// que no entienda: es un archivo escrito a mano.
func ReadPhasePlan(path string) (*PhasePlan, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return parsePhasePlan(f)
}

func parsePhasePlan(r io.Reader) (*PhasePlan, error) {
	plan := &PhasePlan{Templates: map[string][]PhaseGroup{}, Sessions: map[int][2]string{}}
	var (
		errs    []error
		current string      // plantilla abierta ("" = ninguna)
		group   *PhaseGroup // grupo "xN:" abierto
	)
	// appendGroup suma un grupo a la plantilla abierta. Los ejercicios de una
	// sola vuelta seguidos van al mismo grupo (un bloque, no uno por ítem).
	appendGroup := func(g PhaseGroup) {
		groups := plan.Templates[current]
		if n := len(groups); g.Rounds == 1 && n > 0 && groups[n-1].Rounds == 1 {
			groups[n-1].Items = append(groups[n-1].Items, g.Items...)
		} else {
			groups = append(groups, g)
		}
		plan.Templates[current] = groups
	}

	sc := bufio.NewScanner(r)
	for line := 1; sc.Scan(); line++ {
		text := strings.TrimSpace(sc.Text())
		fail := func(format string, args ...any) {
			errs = append(errs, fmt.Errorf("línea %d: "+format, append([]any{line}, args...)...))
		}
		switch {
		case text == "" || strings.HasPrefix(text, "#"):
			continue
		case strings.HasPrefix(text, "@"):
			if group != nil {
				fail("falta el end del grupo")
			}
			current, group = strings.TrimPrefix(text, "@"), nil
			if _, dup := plan.Templates[current]; dup {
				fail("plantilla %q repetida", current)
			}
			plan.Templates[current] = nil
		case phaseSessionLine.MatchString(text):
			m := phaseSessionLine.FindStringSubmatch(text)
			n, _ := strconv.Atoi(m[1])
			if _, dup := plan.Sessions[n]; dup {
				fail("sesión %d repetida", n)
			}
			plan.Sessions[n] = [2]string{m[2], m[3]}
			current = ""
		case current == "":
			fail("%q fuera de una plantilla", text)
		case phaseGroupLine.MatchString(text):
			if group != nil {
				fail("grupo dentro de otro grupo")
			}
			n, _ := strconv.Atoi(phaseGroupLine.FindStringSubmatch(text)[1])
			group = &PhaseGroup{Rounds: n}
		case text == "end":
			if group == nil || len(group.Items) == 0 {
				fail("end sin grupo abierto o grupo vacío")
			} else {
				appendGroup(*group)
			}
			group = nil
		case phaseItemLine.MatchString(text):
			m := phaseItemLine.FindStringSubmatch(text)
			it := PhaseItem{Name: m[1]}
			v, _ := strconv.Atoi(m[2])
			if m[3] == "s" {
				it.DurationS = v
			} else {
				it.Reps = v
			}
			rounds := 1
			if m[4] != "" {
				rounds, _ = strconv.Atoi(m[4])
			}
			switch {
			case group != nil && m[4] != "":
				fail("vueltas propias dentro de un grupo")
			case group != nil:
				group.Items = append(group.Items, it)
			default:
				appendGroup(PhaseGroup{Rounds: rounds, Items: []PhaseItem{it}})
			}
		default:
			fail("no se entiende %q", text)
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if group != nil {
		errs = append(errs, errors.New("falta el end del último grupo"))
	}
	for n, ts := range plan.Sessions {
		for _, t := range ts {
			if _, ok := plan.Templates[t]; !ok {
				errs = append(errs, fmt.Errorf("sesión %d: no existe la plantilla %q", n, t))
			}
		}
	}
	return plan, errors.Join(errs...)
}

// ── Ejercicios ──────────────────────────────────────────────────────────────

// phaseAliases traduce los nombres de las capturas (los de la app original)
// al nombre del ejercicio en el catálogo, cuando no coinciden. La app
// original decía "hombros" donde el índice dice "deltoides", y algunos
// ejercicios tenían otro nombre.
var phaseAliases = map[string]string{
	"Arch hold":        "Superman", // "el opuesto del Hollow hold"
	"Inch worm":        "Escaleras",
	"Codos a rodillas": "Skipping rodillas codos",
	"Saltos cruzados con separación de piernas": "Saltos cruzados",
	"Sentadilla con apertura cadera":            "Sentadilla con apertura de cadera",
	"Puente de hombros":                         "Puente de deltoides",
	"Puente de hombros dinámico":                "Puente de deltoides dinámico",
	"Tabla de hombros dinámica":                 "Tabla de deltoides dinámica",
	"Estiramiento aductores":                    "Estiramiento aductores en pared",
	"Estiramiento isquiosurales":                "Estiramiento isquios",
	"Estiramiento isquiosurales en V":           "Estiramiento isquios en v",
	"Estiramiento pectoral en pared":            "Estiramiento pectorales en pared",
	"Estiramiento pectoral en puerta":           "Estiramiento pectorales en puerta",
	"Estiramiento una pierna":                   "Estiramiento de pierna",
}

// NewExercise es un ejercicio que no está en el índice original y se agrega
// al catálogo junto con el calentamiento y la movilidad.
type NewExercise struct {
	Slug, Name, Description string
	MET                     float64
}

// phaseNewExercises son los ejercicios de las capturas que el índice no
// tiene. El texto es propio (no viene de la fuente).
var phaseNewExercises = []NewExercise{{
	Slug: "colgarse",
	Name: "Colgarse",
	Description: "Colgate de una barra con las manos a la altura de los hombros y los brazos " +
		"estirados. Soltá el cuerpo: hombros, espalda y piernas relajados, sin balancearte. " +
		"Respirá tranquilo y aguantá el tiempo indicado.",
	MET: 2,
}}

// phaseExercise es a qué ejercicio del catálogo apunta un nombre de la
// transcripción.
type phaseExercise struct {
	slug       string
	unilateral bool
}

// resolvePhaseExercises arma el índice nombre → ejercicio para todos los
// nombres de la transcripción. Un nombre que no existe es un error: o falta
// un alias, o hay que agregarlo como ejercicio nuevo.
func resolvePhaseExercises(plan *PhasePlan, cat *Catalog) (map[string]phaseExercise, error) {
	bySlug := make(map[string]*Exercise, len(cat.Exercises))
	for _, e := range cat.Exercises {
		bySlug[e.Slug] = e
	}
	added := map[string]bool{}
	for _, e := range phaseNewExercises {
		added[e.Slug] = true
	}

	out := map[string]phaseExercise{}
	var errs []error
	for _, groups := range plan.Templates {
		for _, g := range groups {
			for _, it := range g.Items {
				if _, done := out[it.Name]; done {
					continue
				}
				name := it.Name
				if alias, ok := phaseAliases[name]; ok {
					name = alias
				}
				slug := Slug(name)
				switch e, ok := bySlug[slug]; {
				case ok:
					out[it.Name] = phaseExercise{slug: e.Slug, unilateral: e.Unilateral}
				case added[slug]:
					out[it.Name] = phaseExercise{slug: slug}
				default:
					errs = append(errs, fmt.Errorf("%q no está en el catálogo", it.Name))
				}
			}
		}
	}
	slices.SortFunc(errs, func(a, b error) int { return strings.Compare(a.Error(), b.Error()) })
	return out, errors.Join(errs...)
}

// ── Bloques ─────────────────────────────────────────────────────────────────

// PhaseBlock es un bloque de calentamiento o movilidad listo para insertar.
// A diferencia de Block, el ejercicio va por slug: el SQL que lo carga se
// aplica sobre una base que ya existe (la de producción), donde los IDs los
// pone la base.
type PhaseBlock struct {
	Phase Phase
	Items []PhaseBlockItem
}

type PhaseBlockItem struct {
	Round, Position int
	ExerciseSlug    string
	Side            Side
	DurationS, Reps int
}

// SessionPhases son los bloques que se agregan a una sesión del programa.
type SessionPhases struct {
	Position int // posición de la sesión en el programa
	Warmup   []PhaseBlock
	Mobility []PhaseBlock
}

// BuildPhases arma, para cada sesión de la transcripción, sus bloques de
// calentamiento y de movilidad. Cada grupo es un bloque "rounds" desplegado
// como los del entrenamiento: una fila por ejercicio y por vuelta. Un
// ejercicio unilateral se hace por los dos lados, derecha y después
// izquierda (como en los programas).
func BuildPhases(plan *PhasePlan, cat *Catalog) ([]SessionPhases, error) {
	exercises, err := resolvePhaseExercises(plan, cat)
	if err != nil {
		return nil, err
	}
	build := func(phase Phase, groups []PhaseGroup) []PhaseBlock {
		blocks := make([]PhaseBlock, 0, len(groups))
		for _, g := range groups {
			b := PhaseBlock{Phase: phase}
			for round := 1; round <= g.Rounds; round++ {
				pos := 0
				for _, it := range g.Items {
					ex := exercises[it.Name]
					sides := []Side{SideNone}
					if ex.unilateral {
						sides = []Side{SideRight, SideLeft}
					}
					for _, side := range sides {
						pos++
						b.Items = append(b.Items, PhaseBlockItem{
							Round: round, Position: pos, ExerciseSlug: ex.slug, Side: side,
							DurationS: it.DurationS, Reps: it.Reps,
						})
					}
				}
			}
			blocks = append(blocks, b)
		}
		return blocks
	}

	numbers := slices.Sorted(maps.Keys(plan.Sessions))
	out := make([]SessionPhases, 0, len(numbers))
	for _, n := range numbers {
		t := plan.Sessions[n]
		out = append(out, SessionPhases{
			Position: n,
			Warmup:   build(PhaseWarmup, plan.Templates[t[0]]),
			Mobility: build(PhaseMobility, plan.Templates[t[1]]),
		})
	}
	return out, nil
}
