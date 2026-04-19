# CLAUDE.md — gcp-cartoonify

Serverless image-to-cartoon service on GCP. Ported from aws-cartoonify. Users
sign in via Firebase email/password (Identity Platform), upload a photo, pick
a style, and a Pub/Sub-driven worker invokes Vertex AI Imagen
(`imagegeneration@006` edit_image) to generate a cartoon. Results live in GCS
for 7 days and are accessed through short-lived V4 signed URLs.

## Architecture

```
Browser (SPA on GCS)
  └── Firebase JS SDK → Identity Platform (email/password) → ID token (JWT)

Browser ──POST /upload-url──→ API Gateway (JWT) → upload_url fn → V4 signed PUT URL
Browser ──PUT (direct)─────→ GCS media bucket (originals/<owner>/<job_id>.<ext>)

Browser ──POST /generate───→ API Gateway (JWT) → submit fn
                                → Firestore (status=submitted)
                                → Pub/Sub cartoonify-jobs
                                       ↓ Eventarc trigger
                             cartoonify-worker fn
                             • Pillow: EXIF strip, 1024×1024 crop/resize
                             • Vertex AI Imagen edit_image (imagegeneration@006)
                             • GCS put cartoons/<owner>/<job_id>.png
                             • Firestore (status=complete)

Browser ──GET /result/{id}──→ result fn   → signed GET URLs
Browser ──GET /history──────→ history fn  → newest 50 for owner
Browser ──DELETE /history/{id}→ delete fn → removes GCS objects + Firestore doc
```

**GCP services:** API Gateway, Cloud Functions 2nd Gen, Pub/Sub (Eventarc),
Firestore (Native), GCS (media + web), Identity Platform, Vertex AI Imagen,
Cloud Build, Cloud Run, IAM.

## Project structure

```
gcp-cartoonify/
├── 01-backend/        Terraform: GCS media bucket, Pub/Sub, service accounts,
│                      IAM, Identity Platform API key, Firestore composite indexes
├── 02-functions/      Terraform + Cloud Function source
│   ├── code/
│   │   ├── upload_url/   POST /upload-url  → V4 signed PUT URL
│   │   ├── submit/       POST /generate    → quota check, Pub/Sub publish
│   │   ├── result/       GET  /result/{id} → status + signed GET URLs
│   │   ├── history/      GET  /history     → last 50 jobs for owner
│   │   ├── delete/       DELETE /history/{id} → GCS + Firestore cleanup
│   │   └── worker/       Pub/Sub-triggered → Imagen + GCS + Firestore
│   ├── functions.tf   Cloud Functions + Cloud Run IAM + API Gateway
│   ├── main.tf        Provider, archives, source bucket
│   └── openapi.yaml.tpl  Per-path Firebase JWT auth spec
├── 03-webapp/         Terraform: public GCS bucket + cartoonify SPA
├── apply.sh           3-phase deploy
├── destroy.sh         Reverse-order teardown
├── api_setup.sh       Enable GCP APIs, Identity Platform, Firestore
├── check_env.sh       Pre-flight validation
└── validate.sh        Post-deploy summary
```

## Deploy / destroy

```bash
./apply.sh    # 01-backend → 02-functions → 03-webapp
./destroy.sh  # 03-webapp → 02-functions → 01-backend
```

**Prerequisites:** `gcloud`, `terraform`, `jq` in PATH;
`credentials.json` (service account key) in repo root with roles:
Cloud Functions, Firestore, GCS, Cloud Run, Cloud Build, IAM,
Identity Platform, API Gateway, API Keys, Pub/Sub, Vertex AI.

## Data model

**Firestore `cartoonify_jobs`** (document ID = job_id):

| Field         | Type | Notes                                          |
|---------------|------|------------------------------------------------|
| owner         | str  | Firebase UID (scopes all queries)              |
| job_id        | str  | `{epoch_ms:013d}-{hex8}` — time-sortable       |
| status        | str  | submitted → processing → complete \| error     |
| style         | str  | pixar_3d \| simpsons \| anime \| comic_book \| watercolor \| pencil_sketch |
| original_key  | str  | `originals/<owner>/<job_id>.<ext>`             |
| cartoon_key   | str  | `cartoons/<owner>/<job_id>.png` (when complete)|
| created_at    | int  | epoch seconds                                  |
| ttl           | int  | created_at + 7 days                            |
| error_message | str  | first 500 chars on failure                     |

**Composite Firestore indexes** (created by 01-backend Terraform):
- `(owner ASC, created_at DESC)` — history query
- `(owner ASC, created_at ASC)` — daily quota count

**GCS `cartoonify-media-<hex>`** (private, 7-day lifecycle):
- `originals/<owner>/<job_id>.<ext>` — browser uploads (V4 signed PUT, ≤5 MB)
- `cartoons/<owner>/<job_id>.png` — worker uploads (Vertex AI output)

## Key differences from aws-cartoonify

| Concern       | AWS                         | GCP                              |
|---------------|-----------------------------|----------------------------------|
| Auth          | Cognito PKCE                | Identity Platform (Firebase SDK) |
| Queue         | SQS                         | Pub/Sub + Eventarc               |
| Job store     | DynamoDB                    | Firestore                        |
| Media store   | S3                          | GCS                              |
| Signed URLs   | SigV4 presigned POST        | V4 signed PUT                    |
| AI model      | Bedrock Stability control   | Vertex AI Imagen edit_image      |
| Worker        | Lambda container image      | Cloud Function 2nd Gen (Python)  |
| Terraform     | 4 phases (incl. Docker)     | 3 phases (no container)          |

## Upload flow (browser)

AWS used presigned POST (FormData). GCP uses a signed PUT URL — simpler:

```javascript
// 1. Get signed PUT URL
const presign = await api('/upload-url', 'POST', { content_type: file.type });

// 2. PUT file directly to GCS
await fetch(presign.upload_url, {
  method: 'PUT',
  headers: { 'Content-Type': file.type },
  body: file,
});

// 3. Submit job
await api('/generate', 'POST', { job_id: presign.job_id, key: presign.key, style });
```
