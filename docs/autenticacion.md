# Autenticación: cómo funciona por detrás

Cómo se autentica un usuario en Naguan, de punta a punta: qué es cada token, quién lo
emite, cómo viaja y cómo lo valida el backend. Con analogías a Spring Security.

## Los actores

```
┌────────────┐   email + contraseña    ┌──────────────────┐
│ App        │ ──────────────────────▶ │ Supabase Auth    │  (servicio "gotrue",
│ (Flutter)  │ ◀────────────────────── │ /auth/v1         │   puerto 54321 en local)
│            │   access + refresh      │ firma con clave  │
│            │   token                 │ PRIVADA (ES256)  │
│            │                         └──────────────────┘
│            │                                  │ publica la clave PÚBLICA
│            │                                  ▼ en /auth/v1/.well-known/jwks.json
│            │   GET /v1/programs      ┌──────────────────┐      ┌──────────┐
│            │   Authorization:        │ API Go           │ ───▶ │ Postgres │
│            │   Bearer <access token> │ valida la firma  │      └──────────┘
│            │ ──────────────────────▶ │ con la clave     │
│            │ ◀────────────────────── │ pública          │
└────────────┘        JSON             └──────────────────┘
```

- **Supabase Auth** es el único que sabe de contraseñas. Las guarda hasheadas (bcrypt) en
  su propio esquema de Postgres (`auth.users`) y emite los tokens.
- **La API Go** nunca ve una contraseña ni guarda sesiones: recibe un token en cada
  request y verifica que lo haya firmado Supabase.
- **La app** guarda los tokens y los manda en cada request.

Es el modelo de Spring Security como **Resource Server** (`oauth2ResourceServer().jwt()`):
alguien más emite los tokens (el Authorization Server) y el backend solo los valida.

## Los dos tokens

Al iniciar sesión, Supabase devuelve dos tokens con funciones distintas:

| | Access token | Refresh token |
|---|---|---|
| Qué es | Un **JWT** firmado | Un string opaco (sin contenido legible) |
| Para qué | Demostrar quién sos en cada request a la API | Conseguir un access token nuevo sin la contraseña |
| A quién se manda | A la API Go (`Authorization: Bearer ...`) | Solo a Supabase Auth |
| Vida | Corta: 1 hora (`jwt_expiry = 3600` en `supabase/config.toml`) | Larga: hasta que se cierra sesión o se revoca |
| Se puede revocar | No: vale hasta que vence | Sí: Supabase lo invalida al cerrar sesión |

**Por qué dos:** el access token viaja en cada request, así que si se filtra conviene que
dure poco. Pero pedir la contraseña cada hora sería insoportable. El refresh token, que
viaja mucho menos, resuelve eso. Además, como el access token no se puede revocar, su
vida corta acota el daño: a lo sumo una hora.

## Anatomía de un access token (JWT)

Un JWT son tres partes en base64url separadas por puntos: `header.payload.firma`.

**Header**: cómo está firmado.
```json
{ "alg": "ES256", "kid": "b81269f1-...", "typ": "JWT" }
```
- `alg`: el algoritmo. **ES256** es ECDSA sobre la curva P-256 con SHA-256: firma
  asimétrica.
- `kid` (*key id*): cuál de las claves del JWKS firmó. Permite rotar claves: durante la
  transición, el JWKS publica la vieja y la nueva.

**Payload** (los *claims*): qué afirma el token. Es legible por cualquiera, **no está
cifrado**: nunca va nada secreto ahí.
```json
{
  "iss": "http://127.0.0.1:54321/auth/v1",   // emisor: quién lo firmó
  "aud": "authenticated",                     // audiencia: para qué sirve
  "sub": "f1ad3595-f536-...",                 // sujeto: el id del usuario
  "email": "prueba@naguan.local",
  "role": "authenticated",
  "iat": 1790873385,                          // emitido (segundos Unix)
  "exp": 1790876985                           // vence (iat + 1 hora)
}
```

**Firma**: Supabase toma `header.payload`, lo hashea y lo firma con su **clave
privada**. Cualquiera con la **clave pública** puede verificar que la firma corresponde a
ese contenido exacto. Si se cambia un solo carácter del payload (por ejemplo, otro `sub`
para hacerse pasar por otro usuario), la firma deja de coincidir.

### Asimétrico (ES256) vs. simétrico (HS256)

Supabase antes firmaba con **HS256**: un secreto compartido que sirve tanto para firmar
como para verificar. El backend tenía que conocer ese secreto, y quien lo tuviera podía
**fabricar** tokens válidos. Con **ES256**, el backend solo tiene la clave pública, que
sirve para verificar pero no para firmar. No hay ningún secreto en el backend.

## Flujo 1: iniciar sesión

```
App                              Supabase Auth                    Postgres (auth.users)
 │ POST /auth/v1/token?grant_type=password
 │ { email, password }  ───────────▶ │
 │                                   │ busca el usuario, compara el
 │                                   │ hash bcrypt de la contraseña ─▶ │
 │                                   │ crea una sesión y firma el JWT
 │ ◀─────────── { access_token, refresh_token, expires_in, user }
 │ guarda la sesión en el teléfono
 │ emite "signedIn" por onAuthStateChange
```

En el código:
- `LoginScreen._submit` → `AuthService.signIn` → `SupabaseAuthService.signIn`, que llama
  a `signInWithPassword` de `supabase_flutter`.
- Si las credenciales no coinciden, Supabase responde `invalid_credentials`, **tanto si
  el email no existe como si la contraseña está mal**. Es a propósito: si dijera "ese
  email no existe", cualquiera podría averiguar quién está registrado.
- `LoginScreen` **no navega** al entrar. `AuthGate` escucha el stream de cambios de sesión
  y cambia de pantalla solo.

## Flujo 2: un request autenticado

```
App                                API Go                                  Postgres
 │ GET /v1/programs
 │ Authorization: Bearer eyJhbGciOiJFUzI1NiIs...
 │ ──────────────────────────────▶ │
 │                                 │ logRequests → recoverPanics → withTimeout
 │                                 │ → requireUser:
 │                                 │     1. saca el token del header
 │                                 │     2. auth.Verifier.Verify(token)
 │                                 │     3. ctx = auth.WithUser(ctx, user)
 │                                 │ → handler (lee el usuario con auth.UserFrom)
 │                                 │ ─────────────────────────────────────▶ │
 │ ◀──────────────────────────── 200 + JSON
```

**Qué verifica `auth.Verifier.Verify`, en orden** (`backend/internal/auth/auth.go`):

1. **Algoritmo**: solo `ES256` (`jwt.WithValidMethods`). Sin esta regla, un atacante
   podría mandar un token con `"alg": "none"` (sin firma) o `"alg": "HS256"` usando la
   clave *pública* como si fuera el secreto. Es el ataque de **algorithm confusion**, y
   un clásico.
2. **Firma**: con la clave pública del JWKS que corresponde al `kid`.
3. **Vencimiento** (`exp`), obligatorio, con 30 segundos de tolerancia por diferencias
   de reloj.
4. **Emisor** (`iss`): que lo haya emitido *nuestro* proyecto de Supabase.
5. **Audiencia** (`aud = authenticated`): que sea un token de usuario y no, por ejemplo,
   una clave de servicio.
6. **Sujeto** (`sub`) no vacío.

Si algo falla, la API responde **401** con el header `WWW-Authenticate: Bearer`. El
motivo exacto (vencido, firma inválida...) va al log del servidor, no al cliente.

**El JWKS se descarga una vez y se cachea** (`keyfunc`): verificar un token es una
operación criptográfica local, sin ir a Supabase en cada request. Si llega un token con
un `kid` desconocido (Supabase rotó la clave), se vuelve a descargar el JWKS.

**Stateless:** la API no guarda sesiones. Cada request trae todo lo necesario para
autenticarse. Por eso escala sin estado compartido entre instancias (varias réplicas en
Cloud Run no necesitan una sesión en común).

### El usuario en el `context`

`requireUser` deja el usuario en el contexto del request con `auth.WithUser`, y los
handlers lo leen con `auth.UserFrom(r.Context())`. Es el `ReactiveSecurityContextHolder`
de WebFlux, pero explícito: viaja en el `ctx` que se pasa de función en función.

La clave del contexto es un tipo privado (`type userKey struct{}`): ningún otro paquete
puede crear la misma clave, así que nadie puede falsificar ni pisar el usuario por
accidente.

## Flujo 3: el token vence (refresh)

```
App (supabase_flutter)                     Supabase Auth
 │ el access token vence en < N segundos
 │ POST /auth/v1/token?grant_type=refresh_token
 │ { refresh_token } ──────────────────────▶ │ valida el refresh token,
 │                                           │ lo marca como usado (rotación)
 │ ◀────────── { access_token NUEVO, refresh_token NUEVO }
 │ guarda la sesión nueva
```

- `supabase_flutter` lo hace solo, **antes** de que el token venza, mientras la app
  está abierta (y al volver al primer plano). Por eso `CatalogClient` recibe una
  *función* `accessToken` y no un string: en cada request lee el token vigente.
- **Rotación de refresh tokens** (`enable_refresh_token_rotation = true`): cada refresh
  token sirve **una sola vez**, y el refresh entrega uno nuevo. Si alguien roba un
  refresh token y lo usa, el legítimo queda inválido al siguiente intento, y Supabase
  detecta la reutilización y revoca la sesión entera. `refresh_token_reuse_interval =
  10` da 10 segundos de gracia por si dos requests concurrentes refrescan a la vez.

## Flujo 4: cerrar sesión

`AuthService.signOut` → `supabase.auth.signOut()`:
1. Le pide a Supabase que **revoque** el refresh token de esta sesión.
2. Borra la sesión guardada en el teléfono.
3. Emite "signedOut": `AuthGate` muestra el ingreso.

El access token que estaba en uso **sigue siendo válido hasta que vence** (como mucho una
hora): un JWT no se puede "des-firmar". Es el costo del modelo stateless.

**Lo vivimos en desarrollo:** después de un `supabase db reset` (que borra los usuarios),
la app seguía con el token del usuario borrado, y ese token pasaba la validación. Al
escribir, la foreign key a `auth.users` lo rechazaba y la API respondía 500. Ahora:

- La API traduce esa violación (`*pgconn.PgError`, código `23503`, restricción
  `workout_user_id_fkey`) a `training.ErrUnknownUser`, y responde **401**.
- La app, ante cualquier 401, llama a `ApiClient.onUnauthorized`, que cierra la sesión:
  `AuthGate` vuelve a mostrar el ingreso. Si alguna vez
hiciera falta revocación inmediata, el backend tendría que consultar una lista de
sesiones revocadas, y se perdería parte de la ventaja.

## Dónde se guarda la sesión en el teléfono

`supabase_flutter` persiste la sesión (incluido el refresh token) con
`shared_preferences`: un archivo privado de la app, **no cifrado**. En Android, otras
apps no pueden leerlo, pero en un teléfono rooteado o con un backup sin cifrar sí.

**Mejora prevista (biometría):** mover el refresh token al **Android Keystore / iOS
Keychain** (`flutter_secure_storage`, cifrado por hardware) y exigir huella o cara
(`local_auth`) para usarlo al abrir la app. La biometría es un candado local: el servidor
nunca ve la huella, y la app solo recibe un "sí/no" del sistema operativo.

## La clave publicable no es un secreto

`supabasePublishableKey` (en `mobile/lib/config.dart`) va dentro del APK, y cualquiera
puede extraerla. Está bien: solo identifica al proyecto y permite llamar a los endpoints
públicos de Auth (como el login). La seguridad la dan las contraseñas y los tokens
firmados. Distinta es la clave **secreta** (*service role*), que saltea todas las reglas:
esa nunca va en una app.

## Autorización: quién puede ver qué

Todo `/v1` exige un usuario. Para los datos de cada usuario (su Senda, sus Fraguas
templadas), **la autorización la hace la API Go**: cada consulta filtra por `user.ID`, que
sale del token verificado, nunca de un parámetro que mande la app.

Un detalle importante: la API se conecta a Postgres como el usuario `postgres`, que no
está sujeto a la Row Level Security (RLS). Las rutas del usuario van bajo `/v1/me/...`: el
usuario sale del token, nunca de la URL.

Como la app no consulta la base directamente, **el acceso por la API REST de Supabase
está cerrado**: RLS activada sin políticas y permisos revocados para `anon` y
`authenticated` (ver `docs/modelo-de-datos.md`, "Seguridad").

## Para probar en local

- Usuario de prueba: `prueba@naguan.local` / `forja-local-123`.
- Crear otro: en Studio (`http://127.0.0.1:54323` → Authentication → Add user), o con la
  API de Auth (`POST /auth/v1/signup`).
- Ver un token por dentro: pegarlo en <https://jwt.io> (solo tokens locales de prueba:
  nunca uno de producción en un sitio externo).
- Probar la API con curl:

```bash
TOKEN=$(curl -s -X POST "http://127.0.0.1:54321/auth/v1/token?grant_type=password" \
  -H "apikey: <clave publicable>" -H 'Content-Type: application/json' \
  -d '{"email":"prueba@naguan.local","password":"forja-local-123"}' | jq -r .access_token)
curl -H "Authorization: Bearer $TOKEN" localhost:8080/v1/me
```

## Pendientes antes de producción

- **Deshabilitar el registro público** (`enable_signup = false`) y crear las cuentas por
  invitación: la app es para vos y algunos amigos.
- **HTTPS** en todo: hoy el emulador habla HTTP plano porque es desarrollo (el
  `usesCleartextTraffic` está solo en el manifiesto de debug).
- **Confirmación de email** y recuperación de contraseña (requieren el envío de mails).

## Resumen: Spring Security ↔ Naguan

| Spring Security (WebFlux) | Naguan |
|---|---|
| Authorization Server (Keycloak, Auth0...) | Supabase Auth |
| `oauth2ResourceServer().jwt()` | Middleware `requireUser` + `auth.Verifier` |
| `spring.security.oauth2.resourceserver.jwt.jwk-set-uri` | `SUPABASE_URL` + `/auth/v1/.well-known/jwks.json` |
| `ReactiveJwtDecoder` | `jwt.ParseWithClaims` con `keyfunc` |
| `ReactiveSecurityContextHolder.getContext()` | `auth.UserFrom(r.Context())` |
| `AuthenticationEntryPoint` (el 401) | `unauthorized()` en `middleware.go` |
| `permitAll()` para `/actuator/health` | `/health` fuera del mux protegido |
