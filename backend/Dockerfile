# Imagen del servidor (cmd/api) para Cloud Run. Dos etapas ("multi-stage"):
#
#   1. build: una imagen con Go compila el binario.
#   2. final: el binario solo, sobre una imagen mínima (distroless) sin shell
#      ni gestor de paquetes. La imagen final pesa ~23 MB, arranca rápido (lo
#      que importa cuando Cloud Run escala desde cero) y tiene muy poca
#      superficie de ataque: no hay nada más que el binario.
#
# Construir y probar en local (desde backend/):
#   docker build -t naguan-api .
#   docker run --rm -p 8080:8080 --add-host=host.docker.internal:host-gateway \
#     -e DATABASE_URL=postgres://postgres:postgres@host.docker.internal:54322/postgres \
#     -e SUPABASE_URL=http://host.docker.internal:54321 \
#     -e SUPABASE_ISSUER=http://127.0.0.1:54321/auth/v1 naguan-api
#
# SUPABASE_ISSUER hace falta solo en local: desde el contenedor se llega a
# Supabase por host.docker.internal, pero los tokens dicen 127.0.0.1.

# ── 1. Compilación ───────────────────────────────────────────────────────────
FROM golang:1.27 AS build

WORKDIR /src

# Primero solo go.mod y go.sum, y se descargan las dependencias. Docker cachea
# cada paso: mientras no cambien las dependencias, este paso no se repite
# aunque cambie el código (el build siguiente es mucho más rápido).
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# CGO_ENABLED=0: binario estático, sin depender de la libc del sistema (la
# imagen final no tiene). -trimpath y -ldflags="-s -w" sacan rutas locales y
# símbolos de depuración: el binario queda más chico.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api

# ── 2. Imagen final ──────────────────────────────────────────────────────────
# distroless/static trae solo lo mínimo para un binario estático: los
# certificados raíz (para hablar HTTPS con Supabase) y las zonas horarias.
# La variante :nonroot corre como un usuario sin privilegios.
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/api /api

# Cloud Run inyecta PORT (el código usa 8080 si no viene). EXPOSE es solo
# documentación.
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/api"]
