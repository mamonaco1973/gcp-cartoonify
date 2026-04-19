# GCP Cartoonify

This project delivers a fully automated **serverless image-to-cartoon service**
on Google Cloud Platform, ported from the AWS Bedrock-based aws-cartoonify
project. Users sign in, upload a photo, choose a cartoon style, and an
asynchronous Pub/Sub-driven worker calls **Vertex AI Imagen** to generate the
cartoon. Results are stored in GCS for 7 days and accessed via short-lived
signed URLs.

Built with **Cloud Functions 2nd Gen**, **Pub/Sub**, **Firestore**, **Cloud API
Gateway**, **Identity Platform**, **Vertex AI**, and **Terraform**.

---

## Architecture

```
Browser (SPA on GCS)
  └── Firebase JS SDK → Identity Platform (email/password) → ID token (JWT)

Browser ──POST /upload-url──→ API Gateway (JWT) → upload_url fn → V4 signed PUT URL
Browser ──PUT (direct)─────→ GCS media bucket   (originals/<owner>/<job_id>.<ext>)

Browser ──POST /generate───→ API Gateway (JWT) → submit fn
                                → Firestore (status=submitted)
                                → Pub/Sub  cartoonify-jobs
                                       ↓ Eventarc trigger
                             cartoonify-worker fn (Cloud Function)
                             • Pillow: EXIF strip, 1024×1024 crop/resize
                             • Vertex AI Imagen imagegeneration@006 edit_image
                             • GCS put  cartoons/<owner>/<job_id>.png
                             • Firestore (status=complete)

Browser ──GET /result/{id}──→ result fn   → job status + signed GET URLs
Browser ──GET /history──────→ history fn  → newest 50 jobs for owner
Browser ──DELETE /history/{id}→ delete fn → removes GCS objects + Firestore doc
```

---

## API Endpoints

All endpoints (except OPTIONS) require `Authorization: Bearer <firebase_id_token>`.

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/upload-url` | Get a V4 signed PUT URL to upload an image to GCS |
| POST | `/generate` | Submit a cartoonify job (after upload completes) |
| GET | `/result/{job_id}` | Poll job status + signed GET URLs for original/cartoon |
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

## Submit Flow (Browser)

```javascript
// 1. Get a V4 signed PUT URL
const presign = await api('/upload-url', 'POST', { content_type: 'image/jpeg' });

// 2. Upload directly to GCS
await fetch(presign.upload_url, {
  method: 'PUT',
  headers: { 'Content-Type': 'image/jpeg' },
  body: file,
});

// 3. Submit the job
const sub = await api('/generate', 'POST', {
  job_id: presign.job_id,
  key:    presign.key,
  style:  'pixar_3d',
});

// 4. Poll for result
// GET /result/{sub.job_id} every 2s until status === 'complete'
```

---

## Obtaining a Token (CLI)

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

* [A Google Cloud Platform Account](https://console.cloud.google.com/)
* [Install gcloud CLI](https://cloud.google.com/sdk/docs/install)
* [Install Terraform](https://developer.hashicorp.com/terraform/install)
* [Install jq](https://stedolan.github.io/jq/download/)
* A GCP service account JSON key file saved as `credentials.json` in the repo root

The service account needs permissions for: Cloud Functions, Firestore, Cloud
Storage, Cloud Run, Cloud Build, IAM, Identity Platform, API Gateway, API Keys,
Pub/Sub, and Vertex AI.

---

## Deploy

Place `credentials.json` in the repo root, then run:

```bash
./apply.sh
```

`apply.sh` runs in three phases:

1. **01-backend** — GCS media bucket, Pub/Sub topic + subscription + DLQ,
   service accounts, IAM bindings, Identity Platform API key, Firestore
   composite indexes.
2. **02-functions** — 5 HTTP Cloud Functions + 1 Pub/Sub worker + API Gateway
   (OpenAPI spec with per-path Firebase JWT auth).
3. **03-webapp** — Public GCS web bucket; generates `config.json` from Terraform
   outputs and deploys the SPA.

---

## Teardown

```bash
./destroy.sh
```

Destroys in reverse order: webapp → functions → backend.

---

## Project Structure

```
gcp-cartoonify/
├── 01-backend/
│   ├── main.tf        Provider, service accounts, IAM bindings
│   ├── gcs.tf         Private media bucket (CORS, 7-day lifecycle)
│   ├── pubsub.tf      cartoonify-jobs topic + subscription + DLQ
│   ├── identity.tf    Identity Platform browser API key
│   └── firestore.tf   Composite indexes for history + quota queries
├── 02-functions/
│   ├── main.tf        Provider, source archives, GCS source bucket
│   ├── functions.tf   6 Cloud Functions + Cloud Run IAM + API Gateway
│   ├── openapi.yaml.tpl  Per-path Firebase JWT OpenAPI spec
│   └── code/
│       ├── upload_url/   POST /upload-url
│       ├── submit/       POST /generate
│       ├── result/       GET  /result/{job_id}
│       ├── history/      GET  /history
│       ├── delete/       DELETE /history/{job_id}
│       └── worker/       Pub/Sub-triggered Vertex AI worker
├── 03-webapp/
│   ├── main.tf
│   ├── public-bucket.tf
│   └── index.html.tmpl  Cartoonify SPA (Firebase Auth)
├── apply.sh
├── destroy.sh
├── api_setup.sh
├── check_env.sh
└── validate.sh
```
