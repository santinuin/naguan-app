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

El APK queda en `build/app/outputs/flutter-apk/app-release.apk` (~53 MB: trae el
código nativo de las tres arquitecturas, ARM de 32 y 64 bits y x86). Con
`--split-per-abi` se generan APKs separados de ~18 MB; para un teléfono moderno alcanza
con el `arm64-v8a`. Se instala pasándolo al
teléfono (habilitando "instalar apps de orígenes desconocidos") o con
`adb install` con el teléfono conectado.

- Producción es todo **HTTPS**: el permiso de HTTP sin cifrar está solo en el manifiesto
  de debug.
- **Firma:** con la clave propia (ver la sección siguiente). Sin `key.properties`, el
  build cae a la clave de debug.

### Clave de firma (keystore)

Android exige que todo APK esté firmado, y **solo instala una actualización si viene
firmada con la misma clave que la versión instalada**. La firma no dice quién sos (no hay
autoridad certificante como en HTTPS): dice que esta versión viene del mismo dueño que la
anterior. Por eso:

- La clave de debug que usa la plantilla de Flutter es distinta en cada PC (vive en
  `~/.android/debug.keystore`): si cambiás de máquina, tus amigos no pueden actualizar.
- **Perder la clave propia es definitivo**: no hay forma de recuperarla ni de reemplazarla
  sin que todos desinstalen la app (y pierdan sus datos locales). Hacé un backup.

Se crea una sola vez, con `keytool` (viene con el JDK):

```bash
mkdir -p ~/.android-keys
keytool -genkeypair -v -keystore ~/.android-keys/naguan-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias naguan
```

Pide una contraseña y unos datos (nombre, organización...; podés poner solo tu nombre).
`-validity 10000` son ~27 años: la clave tiene que durar lo que dure la app. Después, el
archivo `mobile/android/key.properties` (ignorado por git, igual que los `.jks`):

```properties
storeFile=/home/<usuario>/.android-keys/naguan-release.jks
storePassword=<la contraseña>
keyAlias=naguan
keyPassword=<la contraseña>
```

`mobile/android/app/build.gradle.kts` lo lee y firma el release con esa clave. Sin el
archivo (en CI o en otra PC), cae a la de debug para que el build no falle. Para verificar
con qué clave quedó firmado un APK:

```bash
~/Android/Sdk/build-tools/<versión>/apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
```

**Backup:** el `.jks` y las contraseñas, juntos, en un gestor de contraseñas o un
almacenamiento cifrado, fuera de esta PC.

**El primer APK con la clave nueva** no se instala encima del firmado con la de debug
(error `INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Hay que desinstalar la app una vez, lo que
borra sus datos locales. Antes, abrila con señal para que se registren las Fraguas que
hayan quedado en la cola offline.

### Si el build de release muere con "exit code 137"

Es el sistema matando el proceso por falta de memoria. La plantilla de Flutter le da a
Gradle hasta 8 GB de heap (`mobile/android/gradle.properties`), más el daemon de Kotlin
aparte. En este proyecto quedó en 4 GB, que alcanzan; si vuelve a pasar, cerrá el emulador
y Docker durante el build.

### `SUPABASE_ISSUER` en producción

No hace falta: la API llega a Supabase por la misma URL que figura en los tokens
(`https://<ref>.supabase.co`). Solo se usa al correr el contenedor en local, donde la API
llega por `host.docker.internal` pero los tokens dicen `127.0.0.1`.

## Cargar contenido nuevo en producción

`seed.sql` se aplicó **una sola vez**, al crear el proyecto: volver a correrlo
pisaría IDs a los que ya apuntan Fraguas templadas. El contenido que se agrega
después va en archivos aparte que se aplican sobre lo que ya hay. Hoy:
`seed_phases.sql` y `seed_phases_ring_master.sql`, el calentamiento y la
movilidad de Unbreakable y de Ring Master, y `seed_desencadenado.sql`, un programa
completo transcripto a mano (ver `backend/README.md`). Un archivo
por programa: la CLI aplica cada uno una sola vez. Para Unbreakable fue en este
orden (para Ring Master alcanza con el paso 3: la migración, la API y la app ya
estaban):

1. **Migración** (agrega `block.phase`): `supabase db push`.
2. **API** (lee `block.phase` y filtra los Mojones): redesplegar Cloud Run. Va
   después de la migración: la API nueva consulta una columna que antes no existía.
3. **Contenido:** con la cola offline del teléfono vacía y sin una Fragua de
   Unbreakable a medio hacer (las posiciones de los bloques cambian):

   ```bash
   go run ./cmd/seed phases                  # desde backend/
   supabase db push --include-seed --dry-run # tiene que listar solo el archivo nuevo
   supabase db push --include-seed
   ```

   Si el dry-run lista también `seed.sql` con «hash update» (pasa cuando se
   regenera en local después de haberlo aplicado), **no hagas el push así**:
   dejá en `sql_paths` de `supabase/config.toml` solo el archivo nuevo, hacé el
   push y restaurá la lista. Así fue la carga de Ring Master (2026-10-26).

   La CLI registra cada archivo de seed con su hash
   (`supabase_migrations.seed_files`) y corre solo los que todavía no aplicó. El
   script además se protege: si el programa ya tiene calentamiento, aborta sin
   cambiar nada.
4. **App:** un APK nuevo para ver los títulos CALENTAMIENTO / ENTRENAMIENTO /
   MOVILIDAD. La versión anterior sigue funcionando (ignora `phase` y muestra los
   bloques nuevos como bloques comunes).

**Un programa nuevo** (`seed_<programa>.sql`, de `go run ./cmd/seed plans <slug>`:
generá solo ese, así no cambia el hash de los que ya están aplicados) no necesita
migración ni API ni APK nuevos: es el paso 3 solo. El dry-run tiene que
listar únicamente el archivo nuevo (si lista otro con «hash update», el mismo truco
de `sql_paths`). El script aborta si el programa ya existe.

**Completar campos nuevos del plan en lo ya cargado** (`seed_<programa>_detalles.sql`,
de `go run ./cmd/seed plans-update <slug>`): primero la migración que agrega las columnas
(`supabase db push`), después los seeds de detalles con el truco de `sql_paths` (solo
esos archivos, `--include-seed`, y restaurar la lista), después la API y la app. Así
se cargaron los rangos, máximos, extras, notas y sesiones a tiempo (2026-10-31).

**Corregir contenido ya cargado.** Un seed que ya se aplicó no sirve para corregir:
la CLI no lo vuelve a correr como un archivo nuevo, y el de fases además aborta si el
programa ya tiene calentamiento. Una corrección sobre lo que ya está en producción va
como **migración**: se aplica con `supabase db push`, sin
`--include-seed`. En el mismo cambio se corrige el importador, para que una base
nueva salga bien desde el seed (ahí la migración corre antes que los seeds, sobre
tablas vacías, y no hace nada). La migración solo agrega filas: cambiar o borrar
ítems rompería las Fraguas templadas que los referencian. Ejemplo:
`20261030000000_phase_rests.sql` (Enfriá de 10 s entre las vueltas de un mismo
ejercicio del calentamiento y la movilidad, 2026-10-30).

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
