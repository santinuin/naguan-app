// Package planimport importa los planes que se transcriben a mano (los de
// Fitness Revolucionario, que vienen en PDF) a programas de la app. A
// diferencia de mhimport, la fuente no es un Excel con una fila por vuelta
// sino un archivo de texto escrito por nosotros, con bloques descriptos
// como los escribe el libro («3 tandas de 8, 1 minuto de descanso»). El
// importador los despliega al modelo de la base: una fila por ejercicio y
// por vuelta, con los Enfriá en su lugar.
//
// Los ejercicios se nombran como en el catálogo (el de mhimport, más los
// ejercicios nuevos de cada plan): un nombre que no existe es un error.
package planimport

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"

	"github.com/santinuin/naguan-app/backend/internal/mhimport"
)

// La transcripción, con un ejemplo de cada cosa:
//
//	> Descripción del programa (antes de la primera sesión; Markdown).
//
//	@CAL                          ← plantilla de calentamiento o movilidad
//	vueltas x1
//	Saltos de tijera | 25r
//	end
//
//	= 1 | Pirámides: empujar y tirar | CAL MOVSUP   ← sesión, título y fases
//	> Descripción de la sesión.
//	pirámide 1-7-1 | después 60   ← 1, 2, …, 7, …, 1 reps; Enfriá al final
//	Flexión
//	end
//	superset x2 | entre 60 | después 60
//	Flexión diamante | 12r
//	Dominada con manos juntas | 12r
//	end
//	vueltas x3 | entre 60 | después 120
//	Flexión | 8r
//	end
//	tabata x8 20/10              ← 8 vueltas de 20 s de trabajo y 10 de Enfriá
//	Flexión vertical
//	end
//	vueltas x2 | entre 60
//	Sprint | 20s
//	Enfriá | 20s                 ← un Enfriá dentro de la vuelta
//	end
//
//	pirámide 420s | después 60   ← 420 s subiendo de a 1 rep (el peldaño n,
//	Flexión | 1r                    n × 1), bajando y volviendo a subir
//	end
//	amrap 300 | después 120      ← todas las vueltas posibles en 300 s
//	Clean y press | 5r
//	Remo | 5r
//	end
//	tabata x8 20/10 alterna      ← cada vuelta, el ejercicio siguiente
//	Swing
//	Snatch | izq                 ← un solo lado
//	end
//	vueltas x1
//	Levantamiento turco con peso | 300s | alternando   ← sin separar lados
//	end
//
//	= 5 | copia de 1             ← la misma sesión otra vez (otra semana)
//
//	video: Swing | https://youtu.be/…   ← video de un ejercicio nuevo del plan
//
//	incluir barra_libre_comun.txt       ← plantillas y videos de otro archivo
//
//	= 6 | Fuerza A | CAL MOV
//	aproximación Sentadilla con barra   ← series de aproximación (ver abajo)
//	vueltas x3 | entre 120 | después 120
//	Sentadilla con barra | 5r
//	end
//	usar HIIT1                   ← los bloques de una plantilla, en el entrenamiento
//	pirámide 15,9,6              ← las reps de cada vuelta, en orden
//	Thruster con kettlebell
//	end
//
// "aproximación Ejercicio" son las series con peso creciente antes de las de
// trabajo: 5, 5, 5, 3 y 2 reps (con "corta", 5, 3 y 2, para un segundo
// ejercicio del mismo grupo muscular), con 30 s de Enfriá, 60 antes de la de
// 2 y 120 antes de la primera serie de trabajo.
//
// "entre" es el Enfriá entre una vuelta y la siguiente; "después", el que
// separa el bloque del siguiente (en un AMRAP va como bloque aparte: los
// ítems de un AMRAP son la vuelta que se repite). Un ejercicio unilateral se
// hace por los dos lados (derecha y después izquierda), cada uno con la
// medida indicada, salvo que la línea diga el lado ("der", "izq") o
// "alternando" (un solo paso, cambiando de lado como pida el plan).

// BlockKind es cómo está escrito un bloque en la transcripción.
type BlockKind string

const (
	KindRounds   BlockKind = "vueltas"
	KindSuperset BlockKind = "superset"
	KindLadder   BlockKind = "pirámide"
	KindTabata   BlockKind = "tabata"
	KindAMRAP    BlockKind = "amrap"
	// KindPyramid es la pirámide con tope de tiempo («pirámide 420s»): sus
	// ítems son el peldaño modelo, con el incremento como reps.
	KindPyramid BlockKind = "pirámide con tope"
)

// ItemSpec es una línea de un bloque: un ejercicio con su medida, o un
// Enfriá (Rest) con su duración. En las pirámides y los tabatas el
// ejercicio va sin medida: la pone el bloque.
type ItemSpec struct {
	Name      string
	Reps      int
	DurationS int
	Rest      bool
	// Side fija un solo lado de un unilateral; Alternating lo deja en un
	// solo paso sin lado. Sin ninguno de los dos, se hacen ambos lados.
	Side        mhimport.Side
	Alternating bool
}

// BlockSpec es un bloque tal como está escrito.
type BlockSpec struct {
	Kind   BlockKind
	Rounds int
	// Reps de cada vuelta de una pirámide (len(Ladder) == Rounds).
	Ladder []int
	// Trabajo y Enfriá de cada vuelta de un tabata. Con Alternate, cada
	// vuelta hace un solo ejercicio: el siguiente de la lista.
	WorkS, RestS int
	Alternate    bool
	// Tope de un AMRAP.
	TimeCapS int
	// Use, en un bloque de una sesión, es una plantilla cuyos bloques van en
	// su lugar ("usar NOMBRE"). Se reemplaza al terminar de leer.
	Use string
	// Enfriá entre vueltas y al terminar el bloque (0 = ninguno).
	BetweenS, AfterS int
	Items            []ItemSpec
}

// SessionSpec es una sesión del programa. Una copia (CopyOf > 0) repite
// título, descripción, fases y bloques de otra sesión.
type SessionSpec struct {
	Position    int
	Title       string
	Description string
	// Plantillas de calentamiento y de movilidad ("" = ninguna).
	Warmup, Mobility string
	Blocks           []BlockSpec
	CopyOf           int
}

// Plan es la transcripción leída.
type Plan struct {
	Description string
	Templates   map[string][]BlockSpec
	Sessions    []SessionSpec // en orden: Sessions[i].Position == i+1
	Videos      []VideoSpec
}

// VideoSpec es el video de un ejercicio nuevo del plan. Va en la
// transcripción (no en el archivo versionado del catálogo) porque los links
// son de la fuente.
type VideoSpec struct {
	Name, URL string
}

var (
	sessionLine = regexp.MustCompile(`^=\s*(\d+)\s*\|\s*(.+?)\s*(?:\|\s*(\S+)(?:\s+(\S+))?\s*)?$`)
	copyTitle   = regexp.MustCompile(`^copia de (\d+)$`)
	blockLine   = regexp.MustCompile(`^(vueltas|superset|pirámide|tabata|amrap)\b\s*(.*)$`)
	roundsArg   = regexp.MustCompile(`^x(\d+)$`)
	ladderArg   = regexp.MustCompile(`^(\d+)-(\d+)-(\d+)$`)
	ladderList  = regexp.MustCompile(`^\d+(?:,\d+)+$`)
	pyramidArg  = regexp.MustCompile(`^(\d+)s$`)
	tabataArg   = regexp.MustCompile(`^x(\d+)\s+(\d+)/(\d+)(\s+alterna)?$`)
	amrapArg    = regexp.MustCompile(`^(\d+)$`)
	restArg     = regexp.MustCompile(`^(entre|después)\s+(\d+)$`)
	// Nombre, medida opcional y lado opcional: «Swing | 30s | der».
	itemLine     = regexp.MustCompile(`^(.+?)(?:\s*\|\s*(\d+)([sr]))?(?:\s*\|\s*(der|izq|alternando))?$`)
	videoLine    = regexp.MustCompile(`^video:\s*(.+?)\s*\|\s*(\S+)$`)
	includeLine  = regexp.MustCompile(`^incluir\s+(\S+)$`)
	useLine      = regexp.MustCompile(`^usar\s+(\S+)$`)
	approachLine = regexp.MustCompile(`^aproximación\s+(corta\s+)?(.+)$`)
)

// RestName es cómo se escribe un Enfriá dentro de un bloque.
const RestName = "Enfriá"

// ReadPlan lee una transcripción. Corta con error ante cualquier línea que
// no entienda (y junta todos los errores, para corregirlos de una vez). Los
// "incluir" se buscan en la misma carpeta.
func ReadPlan(path string) (*Plan, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	open := func(name string) (io.ReadCloser, error) {
		return os.Open(filepath.Join(filepath.Dir(path), name))
	}
	return parsePlan(f, open)
}

// opener abre un archivo incluido. Es una función (y no os.Open directo)
// para que los tests puedan incluir textos en memoria.
type opener func(name string) (io.ReadCloser, error)

func parsePlan(r io.Reader, open opener) (*Plan, error) {
	plan := &Plan{Templates: map[string][]BlockSpec{}}
	// Las plantillas se arman por puntero, como los bloques de una sesión:
	// así target puede apuntar a cualquiera de los dos.
	templates := map[string]*[]BlockSpec{}
	var (
		errs []error
		// Dónde van los bloques que se leen: la plantilla o la sesión
		// abierta. Es un puntero al slice para que append lo actualice.
		target   *[]BlockSpec
		session  *SessionSpec
		template string
		block    *BlockSpec
		desc     []string // descripción que se está leyendo
	)
	// flushDesc guarda la descripción leída en el programa o en la sesión.
	flushDesc := func() {
		text := strings.Join(desc, "\n")
		desc = nil
		switch {
		case text == "":
		case session != nil:
			session.Description = text
		default:
			plan.Description = text
		}
	}

	sc := bufio.NewScanner(r)
	for line := 1; sc.Scan(); line++ {
		text := strings.TrimSpace(sc.Text())
		fail := func(format string, args ...any) {
			errs = append(errs, fmt.Errorf("línea %d: "+format, append([]any{line}, args...)...))
		}
		if strings.HasPrefix(text, ">") {
			if block != nil || template != "" || (session != nil && len(session.Blocks) > 0) {
				fail("la descripción va antes de los bloques")
			}
			desc = append(desc, strings.TrimSpace(strings.TrimPrefix(text, ">")))
			continue
		}
		if len(desc) > 0 {
			flushDesc()
		}

		switch {
		case text == "" || strings.HasPrefix(text, "#"):
			continue

		case block != nil && text == "end":
			if len(block.Items) == 0 {
				fail("bloque vacío")
			}
			// El peldaño modelo de una pirámide va por reps (el incremento):
			// un tiempo o un Enfriá adentro no tienen sentido.
			if block.Kind == KindPyramid && slices.ContainsFunc(block.Items, func(it ItemSpec) bool { return it.Reps == 0 }) {
				fail("en una pirámide con tope, cada ejercicio va con su incremento en reps (| 1r)")
			}
			*target = append(*target, *block)
			block = nil

		case block != nil:
			it, err := parseItem(text, block.Kind)
			if err != nil {
				fail("%v", err)
				continue
			}
			block.Items = append(block.Items, it)

		case strings.HasPrefix(text, "@"):
			template = strings.TrimPrefix(text, "@")
			if _, dup := templates[template]; dup {
				fail("plantilla %q repetida", template)
			}
			target, session = new([]BlockSpec), nil
			templates[template] = target

		case sessionLine.MatchString(text):
			m := sessionLine.FindStringSubmatch(text)
			n, _ := strconv.Atoi(m[1])
			if want := len(plan.Sessions) + 1; n != want {
				fail("sesión %d fuera de orden (se esperaba la %d)", n, want)
			}
			plan.Sessions = append(plan.Sessions, SessionSpec{
				Position: n, Title: m[2], Warmup: dash(m[3]), Mobility: dash(m[4]),
			})
			session = &plan.Sessions[len(plan.Sessions)-1]
			template, target = "", &session.Blocks
			if c := copyTitle.FindStringSubmatch(m[2]); c != nil {
				session.CopyOf, _ = strconv.Atoi(c[1])
				session.Title = ""
				target = nil // una copia no lleva bloques propios
			}

		case videoLine.MatchString(text):
			m := videoLine.FindStringSubmatch(text)
			plan.Videos = append(plan.Videos, VideoSpec{Name: m[1], URL: m[2]})

		case includeLine.MatchString(text):
			name := includeLine.FindStringSubmatch(text)[1]
			inc, err := readInclude(name, open)
			if err != nil {
				fail("incluir %s: %v", name, err)
				continue
			}
			for t, blocks := range inc.Templates {
				if _, dup := templates[t]; dup {
					fail("incluir %s: plantilla %q repetida", name, t)
				}
				templates[t] = &blocks
			}
			plan.Videos = append(plan.Videos, inc.Videos...)

		case useLine.MatchString(text):
			if session == nil || target == nil {
				fail("«usar» va dentro de una sesión")
				continue
			}
			*target = append(*target, BlockSpec{Use: useLine.FindStringSubmatch(text)[1]})

		case approachLine.MatchString(text):
			if target == nil {
				fail("aproximación fuera de una sesión o plantilla")
				continue
			}
			m := approachLine.FindStringSubmatch(text)
			*target = append(*target, approachBlock(m[2], m[1] != ""))

		case blockLine.MatchString(text):
			if target == nil {
				fail("bloque fuera de una sesión o plantilla")
				continue
			}
			b, err := parseBlockHeader(text)
			if err != nil {
				fail("%v", err)
				continue
			}
			block = &b

		default:
			fail("no se entiende %q", text)
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	flushDesc()
	for name, blocks := range templates {
		plan.Templates[name] = *blocks
	}
	if block != nil {
		errs = append(errs, errors.New("falta el end del último bloque"))
	}
	errs = append(errs, plan.expandUses()...)
	errs = append(errs, plan.check()...)
	return plan, errors.Join(errs...)
}

// readInclude lee un archivo incluido: solo plantillas y videos (sin
// sesiones ni descripción, que son del programa que lo incluye).
func readInclude(name string, open opener) (*Plan, error) {
	if open == nil {
		return nil, errors.New("no se pueden incluir archivos")
	}
	f, err := open(name)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	inc, err := parsePlan(f, open)
	if err != nil {
		return nil, err
	}
	if len(inc.Sessions) > 0 || inc.Description != "" {
		return nil, errors.New("un archivo incluido solo puede tener plantillas y videos")
	}
	return inc, nil
}

// expandUses reemplaza cada "usar NOMBRE" de las sesiones por los bloques de
// la plantilla. Va al final porque la plantilla puede estar más abajo o en
// un archivo incluido.
func (p *Plan) expandUses() []error {
	var errs []error
	for i := range p.Sessions {
		s := &p.Sessions[i]
		var blocks []BlockSpec
		for _, b := range s.Blocks {
			if b.Use == "" {
				blocks = append(blocks, b)
				continue
			}
			t, ok := p.Templates[b.Use]
			if !ok {
				errs = append(errs, fmt.Errorf("sesión %d: no existe la plantilla %q", s.Position, b.Use))
			}
			blocks = append(blocks, t...)
		}
		s.Blocks = blocks
	}
	return errs
}

// approachBlock arma las series de aproximación de un ejercicio: una sola
// vuelta, con los Enfriá entre series y antes de la primera de trabajo.
func approachBlock(name string, short bool) BlockSpec {
	reps := []int{5, 5, 5, 3, 2}
	if short {
		reps = []int{5, 3, 2}
	}
	b := BlockSpec{Kind: KindRounds, Rounds: 1, AfterS: 120}
	for i, r := range reps {
		b.Items = append(b.Items, ItemSpec{Name: name, Reps: r})
		if i < len(reps)-1 {
			rest := 30
			if reps[i+1] == 2 {
				rest = 60
			}
			b.Items = append(b.Items, ItemSpec{Rest: true, DurationS: rest})
		}
	}
	return b
}

// check valida lo que no se puede ver línea por línea: que las plantillas
// existan y que las copias apunten a una sesión anterior que no sea copia.
func (p *Plan) check() []error {
	var errs []error
	for _, s := range p.Sessions {
		fail := func(format string, args ...any) {
			errs = append(errs, fmt.Errorf("sesión %d: "+format, append([]any{s.Position}, args...)...))
		}
		if s.CopyOf > 0 {
			if s.CopyOf >= s.Position || p.Sessions[s.CopyOf-1].CopyOf > 0 {
				fail("copia de %d: tiene que ser una sesión anterior y que no sea copia", s.CopyOf)
			}
			continue
		}
		if len(s.Blocks) == 0 {
			fail("no tiene bloques")
		}
		for _, t := range []string{s.Warmup, s.Mobility} {
			if _, ok := p.Templates[t]; t != "" && !ok {
				fail("no existe la plantilla %q", t)
			}
		}
	}
	return errs
}

// Resolve devuelve la sesión tal como se carga: la original si es una copia.
func (p *Plan) Resolve(s SessionSpec) SessionSpec {
	if s.CopyOf == 0 {
		return s
	}
	orig := p.Sessions[s.CopyOf-1]
	orig.Position, orig.CopyOf = s.Position, s.CopyOf
	return orig
}

func dash(s string) string {
	if s == "-" {
		return ""
	}
	return s
}

// parseBlockHeader lee la línea que abre un bloque: tipo, vueltas (o la
// forma de la pirámide o del tabata) y los Enfriá.
func parseBlockHeader(text string) (BlockSpec, error) {
	m := blockLine.FindStringSubmatch(text)
	b := BlockSpec{Kind: BlockKind(m[1])}
	parts := strings.Split(m[2], "|")
	arg := strings.TrimSpace(parts[0])
	atoi := func(s string) int { n, _ := strconv.Atoi(s); return n }

	switch b.Kind {
	case KindRounds, KindSuperset:
		a := roundsArg.FindStringSubmatch(arg)
		if a == nil {
			return b, fmt.Errorf("%s: falta xN (cuántas vueltas)", b.Kind)
		}
		b.Rounds = atoi(a[1])
	case KindLadder:
		if a := pyramidArg.FindStringSubmatch(arg); a != nil {
			b.Kind, b.Rounds, b.TimeCapS = KindPyramid, 1, atoi(a[1])
			if b.TimeCapS < 1 {
				return b, fmt.Errorf("pirámide: el tope tiene que ser mayor que cero")
			}
			break
		}
		if ladderList.MatchString(arg) {
			for n := range strings.SplitSeq(arg, ",") {
				b.Ladder = append(b.Ladder, atoi(n))
			}
			if slices.Contains(b.Ladder, 0) {
				return b, fmt.Errorf("pirámide %s: las reps tienen que ser mayores que cero", arg)
			}
			b.Rounds = len(b.Ladder)
			break
		}
		a := ladderArg.FindStringSubmatch(arg)
		if a == nil {
			return b, fmt.Errorf("pirámide: se esperaba inicio-pico-fin (1-7-1) o una lista (15,9,6)")
		}
		from, peak, to := atoi(a[1]), atoi(a[2]), atoi(a[3])
		if from < 1 || to < 1 || peak < from || peak < to {
			return b, fmt.Errorf("pirámide %s: el pico tiene que ser el mayor", arg)
		}
		for n := from; n <= peak; n++ {
			b.Ladder = append(b.Ladder, n)
		}
		for n := peak - 1; n >= to; n-- {
			b.Ladder = append(b.Ladder, n)
		}
		b.Rounds = len(b.Ladder)
	case KindTabata:
		a := tabataArg.FindStringSubmatch(arg)
		if a == nil {
			return b, fmt.Errorf("tabata: se esperaba xN trabajo/descanso [alterna], p. ej. x8 20/10")
		}
		b.Rounds, b.WorkS, b.RestS, b.Alternate = atoi(a[1]), atoi(a[2]), atoi(a[3]), a[4] != ""
	case KindAMRAP:
		a := amrapArg.FindStringSubmatch(arg)
		if a == nil || atoi(a[1]) < 1 {
			return b, fmt.Errorf("amrap: falta el tope en segundos, p. ej. amrap 300")
		}
		b.Rounds, b.TimeCapS = 1, atoi(a[1])
	}
	if b.Rounds < 1 {
		return b, fmt.Errorf("%s: al menos una vuelta", b.Kind)
	}

	for _, p := range parts[1:] {
		a := restArg.FindStringSubmatch(strings.TrimSpace(p))
		if a == nil {
			return b, fmt.Errorf("se esperaba «entre S» o «después S», no %q", p)
		}
		if a[1] == "entre" {
			b.BetweenS = atoi(a[2])
		} else {
			b.AfterS = atoi(a[2])
		}
	}
	if b.BetweenS > 0 && b.Rounds == 1 {
		return b, fmt.Errorf("«entre» en un bloque de una sola vuelta")
	}
	return b, nil
}

// parseItem lee una línea de un bloque. En las pirámides y los tabatas la
// medida la pone el bloque, así que el ejercicio va solo (con su lado, si
// hace falta).
func parseItem(text string, kind BlockKind) (ItemSpec, error) {
	measured := kind != KindLadder && kind != KindTabata
	m := itemLine.FindStringSubmatch(text)
	it := ItemSpec{Name: m[1]}
	switch m[4] {
	case "der":
		it.Side = mhimport.SideRight
	case "izq":
		it.Side = mhimport.SideLeft
	case "alternando":
		it.Alternating = true
	}
	hasMeasure := m[2] != ""
	switch {
	case !hasMeasure && measured:
		return ItemSpec{}, fmt.Errorf("%q: falta la medida (| 8r o | 60s)", text)
	case hasMeasure && !measured:
		return ItemSpec{}, fmt.Errorf("%q: en una %s la medida la pone el bloque", text, kind)
	case it.Name == RestName && (!hasMeasure || m[3] == "r"):
		return ItemSpec{}, fmt.Errorf("un Enfriá necesita su duración en segundos")
	case it.Name == RestName && m[4] != "":
		return ItemSpec{}, fmt.Errorf("un Enfriá no tiene lado")
	}
	if !hasMeasure {
		return it, nil
	}

	v, _ := strconv.Atoi(m[2])
	if v < 1 {
		return ItemSpec{}, fmt.Errorf("%q: la medida tiene que ser mayor que cero", text)
	}
	if m[3] == "s" {
		it.DurationS = v
	} else {
		it.Reps = v
	}
	if it.Name == RestName {
		it.Rest, it.Name = true, ""
	}
	return it, nil
}
