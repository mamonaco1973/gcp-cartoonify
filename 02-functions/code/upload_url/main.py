# ================================================================================
# upload_url — POST /upload-url
# ================================================================================
# Issues a V4 signed PUT URL so the browser can upload the original image
# directly to the private GCS media bucket. The signed URL enforces:
#   - Exact Content-Type match
#   - Key path scoped to originals/<owner>/<job_id>.<ext>
#   - 5-minute expiry
#
# Request:  {"content_type": "image/jpeg"}
# Response: {"job_id": "...", "upload_url": "...", "key": "..."}
# ================================================================================

import datetime
import json
import os
import time
import uuid

import google.auth
import google.auth.transport.requests
from google.cloud import storage

MEDIA_BUCKET_NAME = os.environ["MEDIA_BUCKET_NAME"]

ALLOWED_CONTENT_TYPES = {
    "image/jpeg": "jpg",
    "image/png":  "png",
    "image/webp": "webp",
}
MAX_UPLOAD_BYTES = 5 * 1024 * 1024


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
    """Extract Firebase UID from the header injected by API Gateway."""
    import base64
    header = request.headers.get("X-Apigateway-Api-Userinfo", "")
    if not header:
        raise PermissionError("Missing X-Apigateway-Api-Userinfo")
    # base64url may omit padding
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


def _signed_put_url(bucket_name: str, blob_name: str, content_type: str) -> str:
    """Generate a V4 signed PUT URL using the runtime service account."""
    credentials, _ = google.auth.default()
    credentials.refresh(google.auth.transport.requests.Request())

    client = storage.Client(credentials=credentials)
    blob   = client.bucket(bucket_name).blob(blob_name)

    return blob.generate_signed_url(
        version="v4",
        expiration=datetime.timedelta(minutes=5),
        method="PUT",
        content_type=content_type,
        service_account_email=credentials.service_account_email,
        access_token=credentials.token,
    )


def upload_url(request):
    if request.method == "OPTIONS":
        return ("", 204, _cors_headers())

    try:
        owner = _get_owner(request)
    except PermissionError as e:
        return _json(401, {"error": str(e)})

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

    upload_signed_url = _signed_put_url(MEDIA_BUCKET_NAME, key, content_type)

    return _json(200, {
        "job_id":     job_id,
        "key":        key,
        "upload_url": upload_signed_url,
    })
