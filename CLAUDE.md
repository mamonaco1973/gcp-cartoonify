# CLAUDE.md — gcp-identity-app

A serverless, authenticated notes CRUD API on GCP. Ported from gcp-crud-example with Identity Platform (Firebase Auth) and Cloud API Gateway added for per-user data isolation. One Cloud Function handles all five REST operations; Firestore persists data; Cloud API Gateway validates Firebase JWT tokens; a static GCS SPA provides the browser UI.

---

## What This Project Does

Users sign in via the SPA using Firebase email/password auth (Identity Platform). The SPA obtains a Firebase ID token and passes it as `Authorization: Bearer <token>` to Cloud API Gateway. The gateway validates the token against Identity Platform's JWKS, then forwards the request to the Cloud Function with decoded JWT claims in `X-Apigateway-Api-Userinfo`. The function extracts the Firebase UID (`sub`) as the Firestore owner key — scoping all operations to that user.

**Gateway URL after deploy:**
```
https://{gateway-id}-{hash}-uc.a.run.app
```

| Method | Path | Operation |
|--------|------|-----------|
| POST | `/notes` | Create note |
| GET | `/notes` | List user's notes |
| GET | `/notes/{id}` | Get single note |
| PUT | `/notes/{id}` | Update note |
| DELETE | `/notes/{id}` | Delete note |

All endpoints except OPTIONS require `Authorization: Bearer <firebase_id_token>`.

---

## Architecture

```
Browser (SPA on GCS)
     │
     ├── Loads config.json (apiKey, authDomain, projectId, apiBaseUrl)
     ├── Signs in via Firebase JS SDK (email/password)
     │   └── getIdToken() → Firebase ID token (JWT)
     │
     └── API calls: Authorization: Bearer <id_token>
          │
          ▼
     Cloud API Gateway
     - Validates JWT: issuer=securetoken.google.com/{project_id}
     - Passes decoded claims as X-Apigateway-Api-Userinfo header
     - Forwards to Cloud Run using notes-gateway-sa OIDC token
          │
          ▼
     Cloud Function: notes  (Python 3.11, 2nd Gen, private)
     - Extracts owner = claims["sub"]  (Firebase UID)
     - Routes by request.method + request.path
          │
          ▼
     Firestore (Native mode)
     collection: notes
     document key: UUID4
     owner field: Firebase UID (scopes all queries)
```

**Path routing:** API Gateway uses `APPEND_PATH_TO_ADDRESS` to the Cloud Run URI, so the Cloud Function sees the full path (`/notes` or `/notes/{id}`). The function splits on `/` to extract the note ID.

---

## Repository Layout

```
01-functions/
  notes/
    main.py             Python: auth-aware CRUD handlers + router
    requirements.txt    google-cloud-firestore
  main.tf               Terraform: provider (GA + beta), SA, source bucket, Cloud Function
  identity.tf           Terraform: Identity Platform config, browser API key
  api_gateway.tf        Terraform: gateway SA, Cloud Run IAM, API GW API/config/gateway
  openapi.yaml.tpl      API Gateway OpenAPI spec template (project_id + function_uri injected)
02-webapp/
  index.html.tmpl       SPA template — copied to index.html at deploy time
  main.tf               Terraform: GCP provider
  public-bucket.tf      Terraform: public GCS static site + config.json + favicon
api_setup.sh            Enable GCP APIs (incl. Identity Platform, API Gateway), create Firestore
check_env.sh            Pre-flight: verify gcloud/terraform/jq, credentials.json
apply.sh                Full deployment (both phases + validation)
destroy.sh              Teardown in reverse order
validate.sh             End-to-end CRUD smoke test via Firebase REST API
```

---

## Prerequisites

- `gcloud`, `terraform`, `jq` in PATH
- `credentials.json` (GCP service account key) in repo root
- Service account needs: Cloud Functions, Firestore, Cloud Storage, Cloud Run, Cloud Build, IAM, Identity Platform, API Gateway, API Keys

---

## Deployment

```bash
# Full deploy
./apply.sh

# Teardown
./destroy.sh

# Smoke test only (after deploy)
./validate.sh
```

`apply.sh` runs in two phases:
1. **`check_env.sh`** → validates tools, authenticates gcloud, calls `api_setup.sh`
2. **`01-functions`** → Cloud Function, Identity Platform, API Gateway, API key
3. Reads `gateway_url` and `firebase_api_key` from Terraform outputs
4. Generates `02-webapp/config.json` (apiKey, authDomain, projectId, apiBaseUrl)
5. Copies `index.html.tmpl` → `index.html` (no substitution; config loaded at runtime)
6. **`02-webapp`** → public GCS bucket, uploads index.html, config.json, favicon
7. **`validate.sh`** → creates test user, runs full CRUD via API, deletes test user

---

## Terraform Modules

### 01-functions
- `google_service_account` `notes-sa` — Firestore access (roles/datastore.user)
- `google_storage_bucket` — function source code (random suffix)
- `data.archive_file` — zips `notes/` directory
- `google_cloudfunctions2_function` `notes` — Python 3.11, 2nd Gen, HTTP, **private** (no allUsers)
- `google_identity_platform_config` — enables Identity Platform with email/password sign-in
- `google_apikeys_key` `webapp` — browser API key scoped to identitytoolkit.googleapis.com
- `google_service_account` `notes-gateway-sa` — gateway backend auth SA
- `google_cloud_run_service_iam_member` `gateway_invoker` — gateway SA → roles/run.invoker
- `google_api_gateway_api` — API resource
- `google_api_gateway_api_config` — OpenAPI spec (Firebase JWT security + Cloud Run backend)
- `google_api_gateway_gateway` — deployed gateway (us-central1)
- Outputs: `notes_uri`, `gateway_url`, `firebase_api_key`

### 02-webapp
- `google_storage_bucket` `notes-web-{suffix}` with public read
- `google_storage_bucket_object` — uploads index.html, config.json, favicon.ico
- Output: `webapp_url`

---

## Authentication Flow

1. SPA loads `config.json` (apiKey, authDomain, projectId, apiBaseUrl)
2. User submits email + password → Firebase JS SDK calls Identity Platform
3. Firebase returns an ID token (JWT, valid 1 hour, auto-refreshes via `getIdToken()`)
4. SPA includes `Authorization: Bearer <id_token>` on every API request
5. API Gateway validates signature against JWKS, rejects expired/invalid tokens (401)
6. Gateway encodes claims as base64url JSON in `X-Apigateway-Api-Userinfo` header
7. Cloud Function decodes the header, extracts `sub` (Firebase UID), uses it as `owner`

---

## Cloud Function Path Routing

Since requests arrive via API Gateway with `APPEND_PATH_TO_ADDRESS` targeting the Cloud Run URI:

```
request.path = "/notes"       → collection ops (POST → create, GET → list)
request.path = "/notes/{id}"  → item ops (GET → get, PUT → update, DELETE → delete)
```

Path parsing:
```python
parts = request.path.rstrip("/").split("/")  # ["", "notes"] or ["", "notes", "{id}"]
note_id = parts[2] if len(parts) > 2 else None
```

**Firestore data model:**
- Collection: `notes`
- Document ID: UUID4 (same as `id` field)
- Fields: `owner` (Firebase UID), `id`, `title`, `note`, `created_at`, `updated_at`

---

## OpenAPI Security Definition

```yaml
securityDefinitions:
  firebase:
    type: oauth2
    flow: implicit
    x-google-issuer: "https://securetoken.google.com/{project_id}"
    x-google-jwks_uri: "https://www.googleapis.com/.../securetoken@system.gserviceaccount.com"
    x-google-audiences: "{project_id}"
```

OPTIONS operations have no security requirement (CORS preflight passes through freely).

---

## Test Manually

```bash
# Get a Firebase ID token via REST API
API_KEY=$(jq -r '.apiKey' 02-webapp/config.json)
GATEWAY=$(jq -r '.apiBaseUrl' 02-webapp/config.json)

TOKEN=$(curl -sf -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"yourpassword","returnSecureToken":true}' \
  | jq -r '.idToken')

# Create / List / Get / Update / Delete
curl -X POST "${GATEWAY}/notes" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"title":"Hello","note":"World"}'

curl "${GATEWAY}/notes" -H "Authorization: Bearer ${TOKEN}"
```
