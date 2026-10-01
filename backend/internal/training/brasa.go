package training

import "time"

// Brasa es la racha del usuario.
type Brasa struct {
	// Days son los días entrenados de la racha actual (0: apagada).
	Days int `json:"days"`
	// AtRisk indica que la racha se apaga si hoy no entrena: ya faltó un día
	// hábil y hoy (hábil) todavía no templó ninguna Fragua.
	AtRisk bool `json:"at_risk"`
}

// maxMissedWeekdays es cuántos días hábiles seguidos sin entrenar apagan la
// Brasa: se puede parar un día, no dos.
const maxMissedWeekdays = 2

// computeBrasa calcula la racha a partir de los días entrenados (en la zona
// horaria del usuario) y del día de hoy.
//
// Reglas:
//   - Cuenta los días en que el usuario entrenó.
//   - Faltar un día hábil (lunes a viernes) no la apaga; faltar dos seguidos,
//     sí. El fin de semana no cuenta como falta: si se entrena, suma; si no,
//     se saltea. Por eso faltar viernes y lunes son dos faltas seguidas.
//   - Hoy nunca cuenta como falta: el día todavía no terminó.
//
// Es una función pura (no toca la base ni el reloj): todo lo que necesita
// llega por parámetro, así que se testea con un calendario armado a mano.
func computeBrasa(trainedDays []time.Time, today time.Time) Brasa {
	if len(trainedDays) == 0 {
		return Brasa{}
	}
	trained := make(map[time.Time]bool, len(trainedDays))
	earliest := today
	for _, d := range trainedDays {
		d = dateOnly(d)
		trained[d] = true
		if d.Before(earliest) {
			earliest = d
		}
	}
	today = dateOnly(today)

	// Se camina hacia atrás desde hoy, día por día.
	days, missed := 0, 0
	for d := today; !d.Before(earliest); d = d.AddDate(0, 0, -1) {
		switch {
		case trained[d]:
			days++
			missed = 0
		case d.Equal(today) || isWeekend(d):
			// Ni hoy ni el fin de semana cuentan como falta.
		default:
			missed++
		}
		if missed == maxMissedWeekdays {
			break
		}
	}

	return Brasa{
		Days:   days,
		AtRisk: days > 0 && !trained[today] && !isWeekend(today) && missedBefore(trained, today) == maxMissedWeekdays-1,
	}
}

// missedBefore cuenta los días hábiles seguidos sin entrenar justo antes de
// hoy (desde ayer hacia atrás, hasta el último día entrenado).
func missedBefore(trained map[time.Time]bool, today time.Time) int {
	missed := 0
	for d := today.AddDate(0, 0, -1); missed < maxMissedWeekdays; d = d.AddDate(0, 0, -1) {
		if trained[d] {
			break
		}
		if !isWeekend(d) {
			missed++
		}
	}
	return missed
}

func isWeekend(d time.Time) bool {
	wd := d.Weekday()
	return wd == time.Saturday || wd == time.Sunday
}

// dateOnly normaliza a medianoche UTC: así dos time.Time del mismo día son
// iguales como clave de un map, vengan de donde vengan.
func dateOnly(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}
