package auth

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"errors"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const testIssuer = "http://supabase.test/auth/v1"

// newKey genera un par de claves ES256 para el test: la privada firma (lo
// que haría Supabase) y la pública verifica (lo que hace el backend).
func newKey(t *testing.T) *ecdsa.PrivateKey {
	t.Helper()
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return k
}

// sign firma claims con la clave dada, como lo haría Supabase.
func sign(t *testing.T, key *ecdsa.PrivateKey, c jwt.Claims) string {
	t.Helper()
	s, err := jwt.NewWithClaims(jwt.SigningMethodES256, c).SignedString(key)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func validClaims() claims {
	now := time.Now()
	return claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   "f1ad3595-f536-4dbf-9134-95892686ab66",
			Issuer:    testIssuer,
			Audience:  jwt.ClaimStrings{"authenticated"},
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(time.Hour)),
		},
		Email: "prueba@naguan.local",
	}
}

func TestVerify(t *testing.T) {
	key := newKey(t)
	// El verificador solo conoce la clave pública.
	v := newVerifier(func(*jwt.Token) (any, error) { return &key.PublicKey, nil }, testIssuer)

	expired := validClaims()
	expired.ExpiresAt = jwt.NewNumericDate(time.Now().Add(-time.Hour))
	otherIssuer := validClaims()
	otherIssuer.Issuer = "http://otro.test/auth/v1"
	otherAudience := validClaims()
	otherAudience.Audience = jwt.ClaimStrings{"anon"}
	noSubject := validClaims()
	noSubject.Subject = ""

	// Un token HS256 firmado con un secreto cualquiera: el algoritmo no
	// permitido tiene que rechazarse aunque la "firma" sea consistente.
	hs256, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, validClaims()).SignedString([]byte("secreto"))

	tests := []struct {
		name    string
		token   string
		wantErr bool
	}{
		{"válido", sign(t, key, validClaims()), false},
		{"vencido", sign(t, key, expired), true},
		{"otro emisor", sign(t, key, otherIssuer), true},
		{"otra audiencia", sign(t, key, otherAudience), true},
		{"sin sub", sign(t, key, noSubject), true},
		{"firmado con otra clave", sign(t, newKey(t), validClaims()), true},
		{"algoritmo HS256", hs256, true},
		{"basura", "no.es.un.jwt", true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			u, err := v.Verify(tt.token)
			if tt.wantErr {
				if !errors.Is(err, ErrInvalidToken) {
					t.Errorf("err = %v, want ErrInvalidToken", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("err = %v", err)
			}
			if u.ID != "f1ad3595-f536-4dbf-9134-95892686ab66" || u.Email != "prueba@naguan.local" {
				t.Errorf("user = %+v", u)
			}
		})
	}
}

func TestUserContext(t *testing.T) {
	if _, ok := UserFrom(context.Background()); ok {
		t.Error("un contexto vacío no debería tener usuario")
	}

	ctx := WithUser(context.Background(), User{ID: "u1"})
	u, ok := UserFrom(ctx)
	if !ok || u.ID != "u1" {
		t.Errorf("UserFrom = %+v, %v", u, ok)
	}
}
