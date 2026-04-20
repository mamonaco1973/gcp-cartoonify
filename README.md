# GCP Cartoonify

A serverless image-to-cartoon service on Google Cloud Platform. Users sign in
with email and password, upload a photo, choose a cartoon style, and an
asynchronous worker calls **Vertex AI Imagen** to generate the cartoon. Results
are stored in GCS for 7 days and accessed via short-lived V4 signed URLs.

Built with **Cloud Functions 2nd Gen**, **Pub/Sub + Eventarc**, **Firestore**,
**Cloud API Gateway**, **Identity Platform**, **Vertex AI**, and **Terraform**.

---

## Architecture

```
Browser (SPA on GCS)
  └── Firebase JS SDK → Identity Platform (email/password) → ID token (JWT)

Browser ──POST /upload-url──→ API Gateway (JWT) → cartoonify_api fn
                                → V4 signed PUT URL (300s, scoped to owner/job)
Browser ──PUT (direct)─────→ GCS media bucket (originals/<owner>/<job_id>.<ext>)

Browser ──POST /generate───→ API Gateway (JWT) → cartoonify_api fn
                                → Firestore (status=submitted)
                                → Pub/Sub cartoonify-jobs
                                       ↓ Eventarc trigger
                             cartoonify-worker fn
                             • Pillow: EXIF strip, center-square-crop, 1024×1024
                             • Vertex AI Imagen edit_image (subject reference)
                             • GCS put cartoons/<owner>/<job_id>.png
                             • Firestore (status=complete)

Browser ──GET /result/{id}──→ cartoonify_api fn → job status + signed GET URLs
Browser ──GET /history──────→ cartoonify_api fn → newest 50 jobs for owner
Browser ──DELETE /history/{id}→ cartoonify_api fn → removes GCS objects + Firestore doc
```

---

## API Endpoints

All endpoints (except OPTIONS) require `Authorization: Bearer <firebase_id_token>`.

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/upload-url` | Get a V4 signed PUT URL to upload an image directly to GCS |
| POST | `/generate` | Submit a cartoonify job after the upload completes |
| GET | `/result/{job_id}` | Poll job status and get signed GET URLs for original/cartoon |
| GET | `/history` | Newest 50 jobs for the authenticated user |
| DELETE | `/history/{job_id}` | Delete a job and its GCS objects |

---

## Cartoon Styles

| Style ID | Description |
|----------|-------------|
| `pixar_3d` | Pixar 3D animated portrait |
| `simpsons` | The Simpsons flat cel-shaded style |
| `anime` | Japanese anime portrait |
| `comic_book` | Marvel comic book illustration |
| `watercolor` | Fine art watercolor portrait |
| `pencil_sketch` | Detailed graphite sketch |

---

## Upload Flow (Browser)

```javascript
// 1. Get a V4 signed PUT URL
const presign = await api('/upload-url', 'POST', { content_type: 'image/jpeg' });

// 2. PUT the file directly to GCS — no proxy through the API
await fetch(presign.upload_url, {
  method: 'PUT',
  headers: { 'Content-Type': 'image/jpeg' },
  body: file,
});

// 3. Submit the cartoonify job
const job = await api('/generate', 'POST', {
  job_id: presign.job_id,
  key:    presign.key,
  style:  'pixar_3d',
});

// 4. Poll until complete
// GET /result/{job.job_id} every 2s until status === 'complete'
```

---

## CLI Usage

```bash
API_KEY=$(jq -r '.apiKey'    03-webapp/config.json)
GATEWAY=$(jq -r '.apiBaseUrl' 03-webapp/config.json)

TOKEN=$(curl -sf -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"yourpassword","returnSecureToken":true}' \
  | jq -r '.idToken')

# Request an upload URL
curl -s -X POST "${GATEWAY}/upload-url" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"content_type":"image/jpeg"}'

# Poll job status
curl -s "${GATEWAY}/result/<job_id>" -H "Authorization: Bearer ${TOKEN}"

# View history
curl -s "${GATEWAY}/history" -H "Authorization: Bearer ${TOKEN}"
```

---

## Prerequisites

* [A Google Cloud Platform account](https://console.cloud.google.com/)
* [gcloud CLI](https://cloud.google.com/sdk/docs/install)
* [Terraform](https://developer.hashicorp.com/terraform/install)
* [jq](https://stedolan.github.io/jq/download/)
* A GCP service account JSON key saved as `credentials.json` in the repo root

The service account requires roles for: Cloud Functions, Cloud Run, Cloud Build,
Cloud Storage, Firestore, IAM, Identity Platform, API Gateway, API Keys,
Pub/Sub, and Vertex AI.

---

## Deploy

```bash
./apply.sh
```

Runs in three phases:

1. **01-backend** — Private GCS media bucket (CORS, 7-day lifecycle), Pub/Sub
   topic + subscription + DLQ, service accounts, IAM bindings, Identity
   Platform API key.
2. **02-functions** — `cartoonify_api` HTTP Cloud Function (all 5 routes) +
   `cartoonify_worker` Pub/Sub-triggered function + API Gateway (OpenAPI spec
   with Firebase JWT auth).
3. **03-webapp** — Public GCS web bucket, generates `config.json` from Terraform
   outputs, deploys the SPA.

Composite Firestore indexes are created by `api_setup.sh` (called from phase 0)
using `gcloud` rather than Terraform — they survive destroy/apply cycles without
conflict.

---

## Teardown

```bash
./destroy.sh
```

Destroys in reverse order: webapp → functions → backend. Empties the media
bucket and clears Firestore documents before destroying backend resources.

---

## Project Structure

```
gcp-cartoonify/
├── 01-backend/
│   ├── main.tf          Provider, service accounts, IAM bindings, outputs
│   ├── gcs.tf           Private media bucket (CORS, 7-day lifecycle rule)
│   ├── pubsub.tf        cartoonify-jobs topic + subscription + DLQ
│   └── identity.tf      Identity Platform browser API key
├── 02-functions/
│   ├── main.tf          Provider, source archives, GCS source bucket
│   ├── functions.tf     cartoonify_api + cartoonify_worker + API Gateway
│   ├── openapi.yaml.tpl Firebase JWT OpenAPI spec (single global backend)
│   └── code/
│       ├── api/         cartoonify_api — all 5 HTTP routes in one function
│       └── worker/      cartoonify_worker — Pub/Sub → Vertex AI → GCS
├── 03-webapp/
│   ├── main.tf
│   ├── public-bucket.tf
│   └── index.html.tmpl  Cartoonify SPA (Firebase Auth)
├── apply.sh             3-phase deploy
├── destroy.sh           Reverse-order teardown
├── api_setup.sh         Enable GCP APIs, Identity Platform, Firestore indexes
├── check_env.sh         Pre-flight: tools, credentials, model smoke tests
├── imagen-config.sh     Vertex AI model selection (IMAGEN_MODEL_ID, GEMINI_MODEL_ID)
└── validate.sh          Post-deploy smoke test
```
