package training

import (
	"testing"
	"time"
)

// Calendario de octubre de 2026 para leer los casos:
//
//	jue 1  vie 2  sáb 3  dom 4
//	lun 5  mar 6  mié 7  jue 8  vie 9  sáb 10  dom 11
//	lun 12
func oct(day int) time.Time { return time.Date(2026, 10, day, 0, 0, 0, 0, time.UTC) }

func days(ds ...int) []time.Time {
	out := make([]time.Time, len(ds))
	for i, d := range ds {
		out[i] = oct(d)
	}
	return out
}

func TestComputeBrasa(t *testing.T) {
	tests := []struct {
		name    string
		trained []time.Time
		today   time.Time
		want    Brasa
	}{
		{"nunca entrenó", nil, oct(8), Brasa{}},
		{"tres días seguidos, hoy todavía no", days(5, 6, 7), oct(8), Brasa{Days: 3}},
		{"faltar un día hábil no la apaga", days(5, 7), oct(7), Brasa{Days: 2}},
		{"faltar dos días hábiles la apaga", days(5), oct(8), Brasa{}},
		{"el fin de semana no cuenta como falta", days(2), oct(5), Brasa{Days: 1}},
		{"entrenar el fin de semana suma", days(2, 3, 4, 5), oct(5), Brasa{Days: 4}},
		// Faltó el viernes: si hoy (lunes) no entrena, mañana se apaga.
		{"en riesgo: faltó el viernes y hoy es lunes", days(1), oct(5), Brasa{Days: 1, AtRisk: true}},
		{"faltar viernes y lunes la apaga", days(1), oct(6), Brasa{}},
		{"si hoy entrenó, no está en riesgo", days(5, 7), oct(7), Brasa{Days: 2}},
		{"en riesgo un día hábil cualquiera", days(5), oct(7), Brasa{Days: 1, AtRisk: true}},
		// Una racha vieja, cortada, no se suma a la actual.
		{"solo cuenta la racha actual", append(days(5, 6, 7), time.Date(2026, 9, 21, 0, 0, 0, 0, time.UTC)), oct(7), Brasa{Days: 3}},
		// El sábado nunca está en riesgo: el fin de semana es opcional.
		{"sábado sin entrenar no está en riesgo", days(8), oct(10), Brasa{Days: 1}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := computeBrasa(tt.trained, tt.today); got != tt.want {
				t.Errorf("computeBrasa = %+v, want %+v", got, tt.want)
			}
		})
	}
}
