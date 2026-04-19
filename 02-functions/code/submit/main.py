# ================================================================================
# submit — POST /generate
# ================================================================================
# Kicks off a cartoonify job after the browser has uploaded the original via
# the signed PUT URL returned by /upload-url.
#
# Steps:
#   1. Validate style + job_id
#   2. Confirm the original object exists in GCS
#   3. Enforce daily quota (10 per user per UTC day) via Firestore count query
#   4. Write the job document (status=submitted)
#   5. Publish to cartoonify-jobs Pub/Sub topic
#
# Request:  {"job_id": "...", "key": "...", "style": "...", "prompt_extra": "..."}
# Response: 202 {"job_id": "...", "status": "submitted"}
#           429 when daily quota reached
# ================================================================================

import json
import os
import time

import google.auth
import google.auth.transport.requests
from google.cloud import firestore, pubsub_v1, storage

MEDIA_BUCKET_NAME = os.environ["MEDIA_BUCKET_NAME"]
JOBS_TOPIC        = os.environ["JOBS_TOPIC"]
PROJECT_ID        = os.environ["GOOGLE_CLOUD_PROJECT"]

DAILY_QUOTA      = 10
JOB_TTL_SECONDS  = 7 * 24 * 3600
MAX_PROMPT_EXTRA = 500

ALLOWED_STYLES = {
    "pixar_3d", "simpsons", "anime",
    "comic_book", "watercolor", "pencil_sketch",
}

_db        = firestore.Client()
_publisher = pubsub_v1.PublisherClient()
_gcs       = storage.Client()


def _cors_headers():
    origin = os.environ.get("CORS_ALLOW_ORIGIN", "*")
    return {
        "Access-Control-Allow-Origin":  origin,
        "Access-Control-Allow-Methods": "POST,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Max-Age":       "3600",
    }


def _json(status: int, body: dict):
    headers = {"Content-Type": "application/json", **_cors_headers()}
    return (json.dumps(body), status, headers)


def _get_owner(request) -> str:
    import base64
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


def _count_today(owner: str) -> int:
    """Count jobs submitted by this owner since 00:00 UTC today."""
    today_start = (int(time.time()) // 86400) * 86400
    docs = (
        _db.collection("cartoonify_jobs")
        .where("owner", "==", owner)
        .where("created_at", ">=", today_start)
        .stream()
    )
    return sum(1 for _ in docs)


def submit(request):
    if request.method == "OPTIONS":
        return ("", 204, _cors_headers())

    try:
        owner = _get_owner(request)
    except PermissionError as e:
        return _json(401, {"error": str(e)})

    body         = request.get_json(silent=True) or {}
    job_id       = body.get("job_id")
    key          = body.get("key")
    style        = body.get("style")
    prompt_extra = (body.get("prompt_extra") or "").strip()

    if not job_id or not key:
        return _json(400, {"error": "Missing job_id or key"})

    if style not in ALLOWED_STYLES:
        return _json(400, {
            "error":   "Unsupported style",
            "allowed": sorted(ALLOWED_STYLES),
        })

    if len(prompt_extra) > MAX_PROMPT_EXTRA:
        return _json(400, {"error": f"prompt_extra exceeds {MAX_PROMPT_EXTRA} chars"})

    # Guard against a client reusing another user's key
    expected_prefix = f"originals/{owner}/{job_id}."
    if not key.startswith(expected_prefix):
        return _json(400, {"error": "Key does not match owner/job_id"})

    # Confirm the upload actually happened
    try:
        _gcs.bucket(MEDIA_BUCKET_NAME).blob(key).reload()
    except Exception:
        return _json(400, {"error": "Original not uploaded yet"})

    # Daily quota
    count = _count_today(owner)
    if count >= DAILY_QUOTA:
        return _json(429, {
            "error":  f"Daily limit of {DAILY_QUOTA} reached",
            "used":   count,
            "resets": "at 00:00 UTC",
        })

    now = int(time.time())
    doc = {
        "owner":        owner,
        "job_id":       job_id,
        "status":       "submitted",
        "style":        style,
        "original_key": key,
        "created_at":   now,
        "ttl":          now + JOB_TTL_SECONDS,
    }
    if prompt_extra:
        doc["prompt_extra"] = prompt_extra

    _db.collection("cartoonify_jobs").document(job_id).set(doc)

    topic_path = _publisher.topic_path(PROJECT_ID, JOBS_TOPIC)
    _publisher.publish(
        topic_path,
        json.dumps({
            "job_id":       job_id,
            "owner":        owner,
            "style":        style,
            "original_key": key,
            "prompt_extra": prompt_extra,
        }).encode("utf-8"),
    )

    return _json(202, {"job_id": job_id, "status": "submitted"})
