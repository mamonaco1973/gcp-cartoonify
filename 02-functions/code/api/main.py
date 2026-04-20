# ================================================================================
# cartoonify_api — HTTP Cloud Function handling all 5 API routes
# ================================================================================
# Routes (path as seen by the function after APPEND_PATH_TO_ADDRESS):
#   POST   /upload-url          → issue V4 signed PUT URL for GCS upload
#   POST   /generate            → validate, quota check, publish to Pub/Sub
#   GET    /result/{job_id}     → job status + signed GET URLs
#   GET    /history             → newest 50 jobs for the authenticated user
#   DELETE /history/{job_id}    → remove GCS objects + Firestore document
#
# Auth: API Gateway validates the Firebase JWT and injects the decoded claims
# as X-Apigateway-Api-Userinfo (base64url JSON). All handlers extract the
# Firebase UID (sub) from that header as the owner key.
# ================================================================================

import base64
import datetime
import io
import json
import os
import time
import uuid

import google.auth
import google.auth.transport.requests
from google.cloud import firestore, pubsub_v1, storage

# ================================================================================
# Config
# ================================================================================

MEDIA_BUCKET_NAME = os.environ["MEDIA_BUCKET_NAME"]
JOBS_TOPIC        = os.environ.get("JOBS_TOPIC", "cartoonify-jobs")
PROJECT_ID        = os.environ["GOOGLE_CLOUD_PROJECT"]

ALLOWED_CONTENT_TYPES = {
    "image/jpeg": "jpg",
    "image/png":  "png",
    "image/webp": "webp",
}
ALLOWED_STYLES = {
    "pixar_3d", "simpsons", "anime",
    "comic_book", "watercolor", "pencil_sketch",
}
MAX_UPLOAD_BYTES  = 5 * 1024 * 1024
DAILY_QUOTA       = 10
JOB_TTL_SECONDS   = 7 * 24 * 3600
PRESIGNED_GET_TTL = 4 * 3600
MAX_PROMPT_EXTRA  = 500

# Module-scoped clients — reused across warm invocations
_db        = firestore.Client()
_publisher = pubsub_v1.PublisherClient()
_gcs       = storage.Client()


# ================================================================================
# Shared helpers
# ================================================================================

def _cors_headers():
    origin = os.environ.get("CORS_ALLOW_ORIGIN", "*")
    return {
        "Access-Control-Allow-Origin":  origin,
        "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Max-Age":       "3600",
    }


def _json(status: int, body: dict):
    return (json.dumps(body), status, {"Content-Type": "application/json", **_cors_headers()})


def _get_owner(request) -> str:
    """Extract Firebase UID from the header injected by API Gateway."""
    header = request.headers.get("X-Apigateway-Api-Userinfo", "")
    if not header:
        raise PermissionError("Missing X-Apigateway-Api-Userinfo")
    padding = 4 - len(header) % 4
    if padding != 4:
        header += "=" * padding
    claims = json.loads(base64.b64decode(header).decode("utf-8"))
    sub = claims.get("sub") or claims.get("user_id")
    if not sub:
        raise PermissionError("Missing sub claim")
    return sub


def _make_job_id() -> str:
    """Lexicographically time-sortable: <epoch_ms:013d>-<hex8>."""
    ms = int(time.time() * 1000)
    return f"{ms:013d}-{uuid.uuid4().hex[:8]}"


def _get_signing_credentials():
    """Return refreshed credentials for V4 signed URL generation."""
    credentials, _ = google.auth.default()
    credentials.refresh(google.auth.transport.requests.Request())
    return credentials


def _signed_url(blob_name: str, method: str, content_type: str = None,
                expiry_seconds: int = 300, download_filename: str = None) -> str:
    creds  = _get_signing_credentials()
    bucket = _gcs.bucket(MEDIA_BUCKET_NAME)
    blob   = bucket.blob(blob_name)
    kwargs = {
        "version":               "v4",
        "expiration":            datetime.timedelta(seconds=expiry_seconds),
        "method":                method,
        "service_account_email": creds.service_account_email,
        "access_token":          creds.token,
    }
    if content_type:
        kwargs["content_type"] = content_type
    if download_filename:
        kwargs["response_disposition"] = f'attachment; filename="{download_filename}"'
    return blob.generate_signed_url(**kwargs)


# ================================================================================
# Route handlers
# ================================================================================

def _handle_upload_url(request, owner: str):
    """POST /upload-url — return a V4 signed PUT URL scoped to this owner+job."""
    body         = request.get_json(silent=True) or {}
    content_type = body.get("content_type")

    if content_type not in ALLOWED_CONTENT_TYPES:
        return _json(400, {
            "error":   "Unsupported content_type",
            "allowed": sorted(ALLOWED_CONTENT_TYPES.keys()),
        })

    ext    = ALLOWED_CONTENT_TYPES[content_type]
    job_id = _make_job_id()
    key    = f"originals/{owner}/{job_id}.{ext}"

    upload_url = _signed_url(key, "PUT", content_type=content_type, expiry_seconds=300)
    return _json(200, {"job_id": job_id, "key": key, "upload_url": upload_url})


def _handle_submit(request, owner: str):
    """POST /generate — validate, quota check, write Firestore, publish Pub/Sub."""
    body         = request.get_json(silent=True) or {}
    job_id       = body.get("job_id")
    key          = body.get("key")
    style        = body.get("style")
    prompt_extra = (body.get("prompt_extra") or "").strip()

    if not job_id or not key:
        return _json(400, {"error": "Missing job_id or key"})
    if style not in ALLOWED_STYLES:
        return _json(400, {"error": "Unsupported style", "allowed": sorted(ALLOWED_STYLES)})
    if len(prompt_extra) > MAX_PROMPT_EXTRA:
        return _json(400, {"error": f"prompt_extra exceeds {MAX_PROMPT_EXTRA} chars"})

    # Guard against a client reusing another user's key
    if not key.startswith(f"originals/{owner}/{job_id}."):
        return _json(400, {"error": "Key does not match owner/job_id"})

    # Confirm the upload actually completed
    try:
        _gcs.bucket(MEDIA_BUCKET_NAME).blob(key).reload()
    except Exception:
        return _json(400, {"error": "Original not uploaded yet"})

    # Daily quota — count today's jobs for this owner
    today_start = (int(time.time()) // 86400) * 86400
    docs  = (_db.collection("cartoonify_jobs")
               .where("owner", "==", owner)
               .where("created_at", ">=", today_start)
               .stream())
    count = sum(1 for _ in docs)
    if count >= DAILY_QUOTA:
        return _json(429, {
            "error":  f"Daily limit of {DAILY_QUOTA} reached",
            "used":   count,
            "resets": "at 00:00 UTC",
        })

    now = int(time.time())
    doc = {
        "owner": owner, "job_id": job_id, "status": "submitted",
        "style": style, "original_key": key,
        "created_at": now, "ttl": now + JOB_TTL_SECONDS,
    }
    if prompt_extra:
        doc["prompt_extra"] = prompt_extra
    _db.collection("cartoonify_jobs").document(job_id).set(doc)

    topic_path = _publisher.topic_path(PROJECT_ID, JOBS_TOPIC)
    _publisher.publish(topic_path, json.dumps({
        "job_id": job_id, "owner": owner, "style": style,
        "original_key": key, "prompt_extra": prompt_extra,
    }).encode("utf-8"))

    return _json(202, {"job_id": job_id, "status": "submitted"})


def _handle_result(request, owner: str, job_id: str):
    """GET /result/{job_id} — status + signed GET URLs."""
    doc = _db.collection("cartoonify_jobs").document(job_id).get()
    if not doc.exists or doc.to_dict().get("owner") != owner:
        return _json(404, {"error": "Not found"})

    item = doc.to_dict()
    out  = {
        "job_id":     item["job_id"],
        "status":     item.get("status"),
        "style":      item.get("style"),
        "created_at": item.get("created_at"),
    }
    if item.get("original_key"):
        out["original_url"] = _signed_url(
            item["original_key"], "GET", expiry_seconds=PRESIGNED_GET_TTL
        )
    if item.get("cartoon_key"):
        out["cartoon_url"] = _signed_url(
            item["cartoon_key"], "GET", expiry_seconds=PRESIGNED_GET_TTL,
            download_filename=f"cartoonify-{item['job_id']}.png",
        )
    if item.get("error_message"):
        out["error_message"] = item["error_message"]
    return _json(200, out)


def _handle_history(request, owner: str):
    """GET /history — newest 50 jobs for this owner."""
    docs = (_db.collection("cartoonify_jobs")
              .where("owner", "==", owner)
              .order_by("created_at", direction=firestore.Query.DESCENDING)
              .limit(50)
              .stream())

    items = []
    for doc in docs:
        item  = doc.to_dict()
        entry = {
            "job_id":     item.get("job_id"),
            "status":     item.get("status"),
            "style":      item.get("style"),
            "created_at": item.get("created_at"),
        }
        if item.get("original_key"):
            entry["original_url"] = _signed_url(
                item["original_key"], "GET", expiry_seconds=PRESIGNED_GET_TTL
            )
        if item.get("cartoon_key"):
            entry["cartoon_url"] = _signed_url(
                item["cartoon_key"], "GET", expiry_seconds=PRESIGNED_GET_TTL,
                download_filename=f"cartoonify-{item['job_id']}.png",
            )
        if item.get("error_message"):
            entry["error_message"] = item["error_message"]
        items.append(entry)

    return _json(200, {"items": items, "count": len(items)})


def _handle_delete(request, owner: str, job_id: str):
    """DELETE /history/{job_id} — remove GCS objects + Firestore doc."""
    doc_ref = _db.collection("cartoonify_jobs").document(job_id)
    doc     = doc_ref.get()
    if not doc.exists or doc.to_dict().get("owner") != owner:
        return _json(404, {"error": "Not found"})

    item   = doc.to_dict()
    bucket = _gcs.bucket(MEDIA_BUCKET_NAME)
    for key in (item.get("original_key"), item.get("cartoon_key")):
        if key:
            try:
                bucket.blob(key).delete()
            except Exception:
                pass  # best-effort; may already be gone via lifecycle rule

    doc_ref.delete()
    return _json(200, {"job_id": job_id, "deleted": True})


# ================================================================================
# Entry point — router
# ================================================================================

def cartoonify_api(request):
    """HTTP entry point. Routes by method + path segments."""
    if request.method == "OPTIONS":
        return ("", 204, _cors_headers())

    try:
        owner = _get_owner(request)
    except PermissionError as e:
        return _json(401, {"error": str(e)})

    parts    = request.path.rstrip("/").split("/")
    segment1 = parts[1] if len(parts) > 1 else ""
    segment2 = parts[2] if len(parts) > 2 else None
    method   = request.method

    if segment1 == "upload-url" and method == "POST":
        return _handle_upload_url(request, owner)

    if segment1 == "generate" and method == "POST":
        return _handle_submit(request, owner)

    if segment1 == "result" and segment2 and method == "GET":
        return _handle_result(request, owner, segment2)

    if segment1 == "history" and not segment2 and method == "GET":
        return _handle_history(request, owner)

    if segment1 == "history" and segment2 and method == "DELETE":
        return _handle_delete(request, owner, segment2)

    return _json(404, {"error": "Not found"})
