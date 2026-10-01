# Despliegue

Cómo se pone Naguan en producción: la base y la autenticación en **Supabase** (nube), la
API Go en **Google Cloud Run**, y la app como **APK** apuntando a las dos. Costo esperado:
~USD 0/mes dentro de los planes gratuitos.

## Arquitectura en producción

```
Teléfono (APK)
  │  login / renovar token ─────────────▶ Supabase Auth  (https://<ref>.supabase.co/auth/v1)
  │
  │  GET/POST /v1/... + Bearer <token>
  ▼
Cloud Run: naguan-api  (contenedor del Dockerfile, escala a cero)
  │  valida el token con el JWKS de Supabase (clave pública)
  │  DATABASE_URL (Secret Manager) ─────▶ Supabase Postgres (pooler, modo sesión)
```

Región: todo en **São Paulo** (Supabase `sa-east-1`, Cloud Run `southamerica-east1`), lo
más cerca de Córdoba. Que la API y la base estén en la misma región importa más que
cualquier otra cosa para la latencia: cada request hace varias consultas.

## 1. Supabase en la nube

1. En <https://supabase.com/dashboard>: **New project**.
   - Región: **South America (São Paulo)**.
   - Guardá la **contraseña de la base** en un gestor de contraseñas (se usa en el paso 3).
2. Conectá la CLI con tu cuenta y con el proyecto (desde la raíz del repo). `login` abre
   el navegador: corrélo vos (en Claude Code, con `!` adelante).

   ```bash
   supabase login
   supabase link --project-ref <ref>      # el <ref> está en la URL del proyecto
   ```

3. Aplicá el esquema y cargá el catálogo:

   ```bash
   supabase db push --dry-run             # muestra qué migraciones aplicaría
   supabase db push --include-seed        # migraciones + supabase/seed.sql
   ```

   El seed se genera antes con `go run ./cmd/seed sql` (desde `backend/`), como en local.
   `db push` lleva la cuenta de qué migraciones ya aplicó: las próximas veces aplica solo
   las nuevas. **Nunca** se edita una migración que ya se aplicó en la nube.

4. **Autenticación** (Dashboard → Authentication):
   - **Deshabilitá el registro público** ("Allow new users to sign up" → off): la app es
     para vos y algunos amigos. Las cuentas se crean desde el dashboard ("Add user").
   - Creá tu usuario.

5. Anotá estos datos (Project Settings → Data API / API Keys / Database):
   - **Project URL**: `https://<ref>.supabase.co`.
   - **Publishable key** (`sb_publishable_...`): va en la app; no es secreta.
   - **Connection string del pooler, modo Session** (ver abajo).

### ¿Qué connection string usar?

Supabase ofrece tres; la API usa **Session pooler** (puerto **5432** del host
`*.pooler.supabase.com`):

| Opción | Por qué no / por qué sí |
|---|---|
| Directa (`db.<ref>.supabase.co`) | En el plan gratuito es **solo IPv6**, y Cloud Run sale a internet por IPv4. No conecta. |
| Transaction pooler (puerto 6543) | Comparte cada conexión entre clientes por transacción, y no soporta los *prepared statements* que pgx usa por defecto. Haría falta cambiar el modo de pgx. |
| **Session pooler (puerto 5432)** | IPv4, y cada conexión del pool de la API es una sesión completa: pgx funciona sin cambios. |

El usuario del pooler tiene la forma `postgres.<ref>`:
`postgres://postgres.<ref>:<contraseña>@aws-0-sa-east-1.pooler.supabase.com:5432/postgres`.

## 2. Google Cloud

1. En <https://console.cloud.google.com>: creá un proyecto (por ejemplo, `naguan`).
   Cloud Run exige una **cuenta de facturación** (tarjeta), aunque el uso entre en el
   plan gratuito.
2. **Alerta de presupuesto** (Billing → Budgets & alerts): un presupuesto de **USD 1** con
   aviso por email al 50% y al 100%. Supabase gratis no cobra excedentes (frena); Cloud
   Run sí factura si te pasás, así que esta alerta es la red de seguridad.
3. Desde la terminal (`gcloud auth login` abre el navegador: corrélo vos):

   ```bash
   gcloud auth login
   gcloud config set project <id-del-proyecto>
   gcloud services enable run.googleapis.com cloudbuild.googleapis.com \
     artifactregistry.googleapis.com secretmanager.googleapis.com
   ```

4. **La connection string va en Secret Manager**, no en una variable de entorno común: es
   la contraseña de la base. Cloud Run la lee al arrancar.

   ```bash
   printf '%s' 'postgres://postgres.<ref>:<contraseña>@aws-0-sa-east-1.pooler.supabase.com:5432/postgres' \
     | gcloud secrets create database-url --data-file=-

   # La cuenta de servicio con la que corre Cloud Run necesita permiso para leerlo.
   PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project) --format='value(projectNumber)')
   gcloud secrets add-iam-policy-binding database-url \
     --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
     --role=roles/secretmanager.secretAccessor
   ```

   (`printf '%s'` y no `echo`: `echo` agrega un salto de línea al final, que quedaría
   dentro del secreto.)

## 3. Desplegar la API en Cloud Run

Desde `backend/`:

```bash
gcloud run deploy naguan-api \
  --source . \
  --region southamerica-east1 \
  --allow-unauthenticated \
  --set-env-vars SUPABASE_URL=https://<ref>.supabase.co \
  --set-secrets DATABASE_URL=database-url:latest \
  --memory 256Mi \
  --min-instances 0 \
  --max-instances 2
```

- `--source .` sube el código; **Cloud Build** construye la imagen con nuestro
  `Dockerfile` y la guarda en **Artifact Registry**. No hace falta Docker en tu máquina
  para desplegar.
- `--allow-unauthenticated`: Cloud Run no exige una identidad de Google para llamar al
  servicio. La API hace su propia autenticación (el JWT de Supabase en `/v1`), y `/health`
  es público a propósito.
- `--min-instances 0`: **escala a cero**. Sin uso no hay instancias ni costo; el primer
  request después de un rato tarda un poco más (el *cold start*; con una imagen de
  ~23 MB y un binario Go, menos de un segundo).
- `--max-instances 2`: un tope de costo. Aunque algo genere tráfico de más, no puede
  escalar sin límite.
- `PORT` lo inyecta Cloud Run; la API ya lo lee (`internal/config`).

Al terminar, `gcloud` muestra la URL del servicio (`https://naguan-api-....run.app`).
Probala:

```bash
curl https://naguan-api-....run.app/health          # {"status":"ok"}
curl https://naguan-api-....run.app/v1/programs     # 401: falta el token (bien)
```

Los logs (cada request, con status y duración) están en la consola, en Cloud Run →
naguan-api → Logs, o con `gcloud run services logs read naguan-api --region southamerica-east1`.

Para actualizar después de un cambio: el mismo `gcloud run deploy` (cada deploy es una
*revisión* nueva; Cloud Run mueve el tráfico cuando arranca bien, y se puede volver atrás
a una revisión anterior desde la consola).

## 4. La app apuntando a producción

La configuración de la app (`mobile/lib/config.dart`) se pisa al compilar con
`--dart-define`. Desde `mobile/`:

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://naguan-api-....run.app/v1 \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

El APK queda en `build/app/outputs/flutter-apk/app-release.apk`. Se instala pasándolo al
teléfono (habilitando "instalar apps de orígenes desconocidos") o con
`adb install` con el teléfono conectado.

- Producción es todo **HTTPS**: el permiso de HTTP sin cifrar está solo en el manifiesto
  de debug.
- **Firma:** hoy el APK de release se firma con la clave de debug (lo deja así la
  plantilla de Flutter). Para uso personal alcanza; antes de compartirlo con amigos
  conviene crear una clave propia (*keystore*), porque Android solo instala una
  actualización si está firmada con la **misma** clave que la versión instalada.

## 5. Integración continua

`.github/workflows/ci.yml` corre en cada push a `master` y en cada pull request:

- **Backend:** `gofmt`, `go vet`, tests (los de integración se saltean: no hay Postgres),
  que el código de sqlc esté al día (`sqlc diff`) y que la imagen Docker construya.
- **App:** `dart format`, `flutter analyze` y `flutter test`.

Un despliegue automático (CD) desde GitHub a Cloud Run queda para más adelante: por ahora
se despliega a mano, que con un solo desarrollador es más simple y más claro.

## Cuidados del plan gratuito

- **Supabase pausa los proyectos gratuitos tras ~7 días sin actividad.** Se reactivan
  desde el dashboard. Con uso regular no pasa.
- **Supabase gratis:** 500 MB de base, 5 GB de transferencia/mes, 50.000 usuarios
  activos/mes. Una Fragua usa unos pocos KB.
- **Cloud Run:** 2 millones de requests/mes gratis, más un cupo de CPU y memoria. Con
  `--max-instances 2` y la alerta de presupuesto, no hay sorpresas.
