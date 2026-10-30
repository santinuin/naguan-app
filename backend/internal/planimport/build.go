package planimport

import (
	"errors"
	"fmt"
	"maps"
	"slices"
	"strings"

	"github.com/santinuin/naguan-app/backend/internal/mhimport"
)

// Program es el plan listo para insertar. Como el SQL de las fases de
// mhimport, va por slugs y no por IDs: se aplica sobre una base que ya
// existe (la de producción), donde los IDs los pone la base.
type Program struct {
	Slug, Name, Description string
	NewExercises            []mhimport.NewExercise
	Unilateral              map[string]bool // de los ejercicios nuevos
	Progressions            [][2]string     // pares (más fácil, más difícil) por slug
	Videos                  [][2]string     // (slug, url) de ejercicios nuevos
	Sessions                []Session       // en orden de posición
}

type Session struct {
	Title, Description string
	Blocks             []Block
}

// Block es un bloque desplegado. Type es el block_type de la base y Phase
// el block_phase (warmup, main o mobility). TimeCapS, solo en un amrap.
type Block struct {
	Type     string
	Phase    mhimport.Phase
	TimeCapS int
	Items    []Item
}

// Item es una fila de block_item: un ejercicio o, con Rest, un Enfriá (sin
// ejercicio ni lado, solo DurationS).
type Item struct {
	Round, Position int
	ExerciseSlug    string
	Side            mhimport.Side
	DurationS, Reps int
	Rest            bool
}

const phaseMain mhimport.Phase = "main"

// exerciseInfo es lo que el armado necesita saber de un ejercicio.
type exerciseInfo struct {
	slug       string
	unilateral bool
}

// Build arma el programa: resuelve cada nombre contra el catálogo (más los
// ejercicios nuevos del plan) y despliega los bloques. Junta todos los
// nombres que no encuentra antes de cortar.
func Build(slug, name string, plan *Plan, extras *CatalogExtras, cat *mhimport.Catalog) (*Program, error) {
	known := map[string]exerciseInfo{}
	for _, e := range cat.Exercises {
		known[e.Slug] = exerciseInfo{e.Slug, e.Unilateral}
	}
	for _, e := range mhimport.PhaseNewExercises {
		known[e.Slug] = exerciseInfo{slug: e.Slug}
	}
	for _, e := range extras.Exercises {
		if _, dup := known[e.Slug]; dup {
			return nil, fmt.Errorf("%q ya está en el catálogo: no es un ejercicio nuevo", e.Name)
		}
		known[e.Slug] = exerciseInfo{e.Slug, extras.Unilateral[e.Slug]}
	}

	// missing junta los nombres sin resolver (sin repetir); bad, los demás
	// errores de armado (un lado en un ejercicio que no tiene lados...).
	missing := map[string]bool{}
	var bad []error
	resolve := func(name string) exerciseInfo {
		info, ok := known[mhimport.Slug(name)]
		if !ok {
			missing[name] = true
		}
		return info
	}

	prog := &Program{
		Slug: slug, Name: name, Description: plan.Description,
		NewExercises: extras.Exercises, Unilateral: extras.Unilateral,
	}
	for _, chain := range extras.Chains {
		for i := 1; i < len(chain); i++ {
			prog.Progressions = append(prog.Progressions,
				[2]string{resolve(chain[i-1]).slug, resolve(chain[i]).slug})
		}
	}

	isNew := map[string]bool{}
	for _, e := range extras.Exercises {
		isNew[e.Slug] = true
	}
	for _, v := range plan.Videos {
		slug := resolve(v.Name).slug
		if slug != "" && !isNew[slug] {
			bad = append(bad, fmt.Errorf("video de %q: solo los ejercicios nuevos llevan video del plan", v.Name))
		}
		prog.Videos = append(prog.Videos, [2]string{slug, v.URL})
	}

	expand := func(phase mhimport.Phase, specs []BlockSpec) []Block {
		blocks := make([]Block, 0, len(specs))
		for _, spec := range specs {
			bs, err := expandBlock(phase, spec, resolve)
			if err != nil {
				bad = append(bad, err)
			}
			blocks = append(blocks, bs...)
		}
		return blocks
	}
	for _, spec := range plan.Sessions {
		s := plan.Resolve(spec)
		var blocks []Block
		blocks = append(blocks, expand(mhimport.PhaseWarmup, plan.Templates[s.Warmup])...)
		blocks = append(blocks, expand(phaseMain, s.Blocks)...)
		blocks = append(blocks, expand(mhimport.PhaseMobility, plan.Templates[s.Mobility])...)
		prog.Sessions = append(prog.Sessions, Session{Title: s.Title, Description: s.Description, Blocks: blocks})
	}

	errs := bad
	for _, name := range slices.Sorted(maps.Keys(missing)) {
		errs = append(errs, fmt.Errorf("%q no está en el catálogo ni entre los ejercicios nuevos", name))
	}
	if len(errs) > 0 {
		return nil, errors.Join(errs...)
	}
	return prog, nil
}

// expandBlock despliega un bloque: una fila por ejercicio, por lado y por
// vuelta, con los Enfriá que pide la transcripción. Devuelve más de un
// bloque solo en un AMRAP con "después": el Enfriá va en un bloque propio,
// porque los ítems del AMRAP son la vuelta que se repite.
func expandBlock(phase mhimport.Phase, spec BlockSpec, resolve func(string) exerciseInfo) ([]Block, error) {
	b := Block{Type: blockType(spec), Phase: phase, TimeCapS: spec.TimeCapS}
	var errs []error
	for round := 1; round <= spec.Rounds; round++ {
		pos := 0
		add := func(it Item) {
			pos++
			it.Round, it.Position = round, pos
			b.Items = append(b.Items, it)
		}
		items := spec.Items
		if spec.Alternate {
			// Un ejercicio por vuelta, rotando por la lista.
			items = []ItemSpec{spec.Items[(round-1)%len(spec.Items)]}
		}
		for _, it := range items {
			if it.Rest {
				add(Item{Rest: true, DurationS: it.DurationS})
				continue
			}
			reps, dur := it.Reps, it.DurationS
			switch spec.Kind {
			case KindLadder:
				reps = spec.Ladder[round-1]
			case KindTabata:
				dur = spec.WorkS
			}
			ex := resolve(it.Name)
			var sides []mhimport.Side
			switch {
			case (it.Side != mhimport.SideNone || it.Alternating) && ex.slug != "" && !ex.unilateral:
				errs = append(errs, fmt.Errorf("%q no es unilateral: no lleva lado ni alternando", it.Name))
				sides = []mhimport.Side{mhimport.SideNone}
			case it.Side != mhimport.SideNone:
				sides = []mhimport.Side{it.Side}
			case ex.unilateral && !it.Alternating:
				sides = []mhimport.Side{mhimport.SideRight, mhimport.SideLeft}
			default:
				sides = []mhimport.Side{mhimport.SideNone}
			}
			for _, side := range sides {
				add(Item{ExerciseSlug: ex.slug, Side: side, Reps: reps, DurationS: dur})
			}
		}
		// El Enfriá del tabata va después de cada vuelta; el "entre", solo
		// entre vueltas; el "después", al terminar la última.
		last := round == spec.Rounds
		switch {
		case spec.Kind == KindTabata && !last:
			add(Item{Rest: true, DurationS: spec.RestS})
		case spec.BetweenS > 0 && !last:
			add(Item{Rest: true, DurationS: spec.BetweenS})
		case spec.AfterS > 0 && last && spec.Kind != KindAMRAP:
			add(Item{Rest: true, DurationS: spec.AfterS})
		}
	}
	blocks := []Block{b}
	if spec.Kind == KindAMRAP && spec.AfterS > 0 {
		blocks = append(blocks, Block{Type: "rounds", Phase: phase, Items: []Item{
			{Round: 1, Position: 1, Rest: true, DurationS: spec.AfterS},
		}})
	}
	return blocks, errors.Join(errs...)
}

// blockType traduce el tipo de la transcripción al block_type de la base.
// Las vueltas con Enfriá entre ellas son rounds_with_rest, como en los
// programas de Mammoth Hunters.
func blockType(spec BlockSpec) string {
	switch spec.Kind {
	case KindAMRAP:
		return "amrap"
	case KindSuperset:
		return "superset"
	case KindLadder:
		return "ladder"
	case KindTabata:
		return "tabata"
	}
	if spec.BetweenS > 0 || slices.ContainsFunc(spec.Items, func(it ItemSpec) bool { return it.Rest }) {
		return "rounds_with_rest"
	}
	return "rounds"
}

// String resume un programa armado (para el mensaje del comando).
func (p *Program) String() string {
	var blocks, items int
	for _, s := range p.Sessions {
		blocks += len(s.Blocks)
		for _, b := range s.Blocks {
			items += len(b.Items)
		}
	}
	return strings.Join([]string{
		fmt.Sprintf("%d sesiones", len(p.Sessions)),
		fmt.Sprintf("%d bloques", blocks),
		fmt.Sprintf("%d ítems", items),
		fmt.Sprintf("%d ejercicios nuevos", len(p.NewExercises)),
		fmt.Sprintf("%d progresiones", len(p.Progressions)),
		fmt.Sprintf("%d videos", len(p.Videos)),
	}, ", ")
}
