package mhimport

import "testing"

func TestSplitSide(t *testing.T) {
	tests := []struct {
		in       string
		wantBase string
		wantSide Side
	}{
		{"Plancha lateral (derecha)", "Plancha lateral", SideRight},
		{"Plancha lateral (izquierda)", "Plancha lateral", SideLeft},
		{"Estiramiento pectoral menor (I)", "Estiramiento pectoral menor", SideLeft},
		{"Supinación y pronación c/ bastón D", "Supinación y pronación c/ bastón", SideRight},
		{"Rotaciones torácicas c/ rodillas I", "Rotaciones torácicas c/ rodillas", SideLeft},
		{"Contracírculos de deltoides Izq", "Contracírculos de deltoides", SideLeft},
		{"Thruster con kettlebell izquierdo", "Thruster con kettlebell", SideLeft},
		{"Flexión", "Flexión", SideNone},
		// Una letra minúscula es una variante, no un lado.
		{"Flow d", "Flow d", SideNone},
		{"Flexión en L", "Flexión en L", SideNone},
		// "Dominada" termina en "a", no en una palabra de lado.
		{"Dominada", "Dominada", SideNone},
	}
	for _, tt := range tests {
		base, side := SplitSide(tt.in)
		if base != tt.wantBase || side != tt.wantSide {
			t.Errorf("SplitSide(%q) = (%q, %q), want (%q, %q)",
				tt.in, base, side, tt.wantBase, tt.wantSide)
		}
	}
}

func TestNormalizeName(t *testing.T) {
	tests := []struct{ in, want string }{
		{"Saltos cruzados ", "Saltos cruzados"},
		{"Dislocaciones de deltoides c/ banda", "Dislocaciones de deltoides con banda"},
		{"Thruster con KB", "Thruster con kettlebell"},
		{"Peso muerto 1 pierna con KB", "Peso muerto a una pierna con kettlebell"},
		{"Levantamiento de cadera a 1 pierna", "Levantamiento de cadera a 1 pierna"},
		{"abrazos al sol", "Abrazos al sol"},
	}
	for _, tt := range tests {
		if got := NormalizeName(tt.in); got != tt.want {
			t.Errorf("NormalizeName(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestSlug(t *testing.T) {
	tests := []struct{ in, want string }{
		{"Flexión en L", "flexion-en-l"},
		{"Psoas ilíaco", "psoas-iliaco"},
		{"Muscle-up 2", "muscle-up-2"},
		{"  Cuádriceps ", "cuadriceps"},
	}
	for _, tt := range tests {
		if got := Slug(tt.in); got != tt.want {
			t.Errorf("Slug(%q) = %q, want %q", tt.in, got, tt.want)
		}
	}
}
