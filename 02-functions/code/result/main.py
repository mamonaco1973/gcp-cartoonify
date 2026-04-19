# ================================================================================
# result — GET /result/{job_id}
# ================================================================================
# Returns current status of a single job plus V4 signed GET URLs for the
# original and cartoon when available. Used by the SPA to poll after submission.
#
# Response (200):
#   {
#     "job_id": "...",
#     "status": "submitted|processing|complete|error",
#     "style":  "...",
#     "created_at": 1700000000,
#     "original_url": "...",     # signed, always present after upload
#     "cartoon_url":  "...",     # signed, only when status=complete
#     "error_message": "..."     # only when status=error
#   }
# ================================================================================

import base64
import datetime
import json
import os

import google.auth
import google.auth.transport.requests
from google.cloud import firestore, storage

MEDIA_BUCKET_NAME  = os.environ["MEDIA_BUCKET_NAME"]
PRESIGNED_GET_TTL  = 4 * 3600  # 4 hours — matches aws-cartoonify

_db  = firestore.Client()


def _cors_headers():
    origin = os.environ.get("CORS_ALLOW_ORIGIN", "*")
    return {
        "Access-Control-Allow-Origin":  origin,
        "Access-Control-Allow-Methods": "GET,OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type,Authorization",
        "Access-Control-Max-Age":       "3600",
    }


def _json(status: int, body: dict):
    headers = {"Content-Type": "application/json", **_cors_headers()}
    return (json.dumps(body), status, headers)


def _get_owner(request) -> str:
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


def _signed_get_url(blob_name: str, download_filename: str = None) -> str:
    credentials, _ = google.auth.default()
    credentials.refresh(google.auth.transport.requests.Request())
    client = storage.Client(credentials=credentials)
    blob   = client.bucket(MEDIA_BUCKET_NAME).blob(blob_name)

    kwargs = {
        "version":    "v4",
        "expiration": datetime.timedelta(seconds=PRESIGNED_GET_TTL),
        "method":     "GET",
        "service_account_email": credentials.service_account_email,
        "access_token":          credentials.token,
    }
    if download_filename:
        kwargs["response_disposition"] = f'attachment; filename="{download_filename}"'

    return blob.generate_signed_url(**kwargs)


def result(request):
    if request.method == "OPTIONS":
        return ("", 204, _cors_headers())

    try:
        owner = _get_owner(request)
    except PermissionError as e:
        return _json(401, {"error": str(e)})

    # API Gateway appends the path variable; extract last path segment
    job_id = request.path.rstrip("/").split("/")[-1]
    if not job_id:
        return _json(400, {"error": "Missing job_id"})

    doc = _db.collection("cartoonify_jobs").document(job_id).get()
    if not doc.exists:
        return _json(404, {"error": "Not found"})

    item = doc.to_dict()

    # Enforce ownership — users may only view their own jobs
    if item.get("owner") != owner:
        return _json(404, {"error": "Not found"})

    out = {
        "job_id":     item["job_id"],
        "status":     item.get("status"),
        "style":      item.get("style"),
        "created_at": item.get("created_at"),
    }

    if item.get("original_key"):
        out["original_url"] = _signed_get_url(item["original_key"])

    if item.get("cartoon_key"):
        out["cartoon_url"] = _signed_get_url(
            item["cartoon_key"],
            f"cartoonify-{item['job_id']}.png",
        )

    if item.get("error_message"):
        out["error_message"] = item["error_message"]

    return _json(200, out)
