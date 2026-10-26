package mhimport

import (
	"strings"
	"testing"
)

func TestSessionTitles(t *testing.T) {
	titles, err := parseSessionTitles(strings.NewReader(
		"program,position,title\nunbreakable,2,Fuerza 1\nunbreakable,1,General 1\n"))
	if err != nil {
		t.Fatal(err)
	}
	p := &Program{Slug: "unbreakable", Sessions: []*Session{{Title: "Sesión 1"}, {Title: "Sesión 2"}, {Title: "Sesión 3"}}}
	if err := titles.Apply([]*Program{p}); err != nil {
		t.Fatal(err)
	}
	if got := []string{p.Sessions[0].Title, p.Sessions[1].Title, p.Sessions[2].Title}; got[0] != "General 1" ||
		got[1] != "Fuerza 1" || got[2] != "Sesión 3" {
		t.Errorf("títulos = %v", got)
	}

	// Un programa o una posición que no existen son errores de tipeo.
	bad, _ := parseSessionTitles(strings.NewReader("program,position,title\nunbreakable,9,X\nprimall,1,Y\n"))
	if err := bad.Apply([]*Program{p}); err == nil ||
		!strings.Contains(err.Error(), "sesión 9") || !strings.Contains(err.Error(), "primall") {
		t.Errorf("err = %v", err)
	}
	if _, err := parseSessionTitles(strings.NewReader("program,position,title\nunbreakable,1,\n")); err == nil {
		t.Error("título vacío: sin error")
	}
}
