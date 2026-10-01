// Package auth valida los tokens de acceso (JWT) que emite Supabase Auth y
// transporta el usuario autenticado en el context.Context del request.
//
// Supabase firma los tokens con ES256 (curva elíptica): una clave privada que
// solo tiene Supabase firma, y la clave pública, publicada en un JWKS,
// alcanza para verificar. El backend no guarda ningún secreto.
package auth

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/golang-jwt/jwt/v5"
)

// User es el usuario autenticado de un request.
type User struct {
	ID    string // el "sub" del token: el UUID del usuario en Supabase
	Email string
}

// ErrInvalidToken agrupa cualquier problema con el token: ausente, mal
// formado, vencido, mal firmado o emitido para otro destino. Al cliente le
// alcanza con saber que no es válido (401); el detalle va al log.
var ErrInvalidToken = errors.New("token inválido")

// Verifier valida tokens de Supabase.
type Verifier struct {
	keyfunc jwt.Keyfunc
	issuer  string
}

// NewVerifier arma un verificador para el proyecto de Supabase en
// supabaseURL (p. ej. http://127.0.0.1:54321), que acepta tokens del emisor
// issuer (p. ej. http://127.0.0.1:54321/auth/v1). Son dos datos y no uno:
// la dirección por la que se llega a Supabase no siempre es la que Supabase
// pone como emisor en sus tokens.
//
// Las claves públicas se descargan del JWKS del proyecto y se refrescan en
// segundo plano (si Supabase rota la clave, aparece un "kid" nuevo y se
// vuelve a descargar). Ese refresco vive mientras viva ctx: main le pasa un
// contexto que se cancela al apagar el servidor.
func NewVerifier(ctx context.Context, supabaseURL, issuer string) (*Verifier, error) {
	base := strings.TrimSuffix(supabaseURL, "/")
	jwks, err := keyfunc.NewDefaultCtx(ctx, []string{base + "/auth/v1/.well-known/jwks.json"})
	if err != nil {
		return nil, fmt.Errorf("cargando las claves públicas de Supabase: %w", err)
	}
	return newVerifier(jwks.Keyfunc, issuer), nil
}

// newVerifier recibe la función que da la clave pública para un token: los
// tests le pasan una clave generada en el momento, sin red.
func newVerifier(kf jwt.Keyfunc, issuer string) *Verifier {
	return &Verifier{keyfunc: kf, issuer: issuer}
}

// claims son los campos del token que nos interesan. jwt.RegisteredClaims
// trae los estándar (sub, iss, aud, exp...); embebido, sus campos y métodos
// pasan a ser de claims.
type claims struct {
	jwt.RegisteredClaims
	Email string `json:"email"`
}

// Verify valida el token y devuelve el usuario. Chequea, en este orden:
// algoritmo, firma, vencimiento, emisor y audiencia.
func (v *Verifier) Verify(token string) (User, error) {
	var c claims
	_, err := jwt.ParseWithClaims(token, &c, v.keyfunc,
		// Solo ES256. Sin esta lista, un atacante podría mandar un token con
		// "alg": "none" o "HS256" y que la librería lo acepte con otra
		// lógica de verificación (el clásico ataque de "algorithm
		// confusion").
		jwt.WithValidMethods([]string{"ES256"}),
		jwt.WithIssuer(v.issuer),
		jwt.WithAudience("authenticated"),
		jwt.WithExpirationRequired(),
		// Tolerancia por diferencias de reloj entre Supabase y el backend.
		jwt.WithLeeway(30*time.Second),
	)
	if err != nil {
		return User{}, fmt.Errorf("%w: %w", ErrInvalidToken, err)
	}
	if c.Subject == "" {
		return User{}, fmt.Errorf("%w: sin sub", ErrInvalidToken)
	}
	return User{ID: c.Subject, Email: c.Email}, nil
}

// ── El usuario en el context ────────────────────────────────────────────────

// userKey es la clave para guardar el usuario en el context. Es un tipo
// propio y sin exportar: ningún otro paquete puede crear la misma clave, así
// que nadie puede pisar ni falsificar el usuario por accidente (con una
// string como clave, cualquiera podría).
type userKey struct{}

// WithUser devuelve un contexto hijo que lleva el usuario. Los contextos son
// inmutables: no se modifica el original, se crea uno nuevo que lo envuelve.
func WithUser(ctx context.Context, u User) context.Context {
	return context.WithValue(ctx, userKey{}, u)
}

// UserFrom devuelve el usuario del contexto, si lo hay. Es el equivalente a
// ReactiveSecurityContextHolder.getContext() de Spring WebFlux, pero
// explícito: el usuario viaja en el ctx que se pasa de función en función.
func UserFrom(ctx context.Context) (User, bool) {
	u, ok := ctx.Value(userKey{}).(User)
	return u, ok
}
