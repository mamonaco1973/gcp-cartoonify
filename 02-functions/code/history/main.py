# ================================================================================
# history — GET /history
# ================================================================================
# Returns up to the 50 newest jobs for the authenticated user, newest first.
# Each entry includes signed GET URLs for the original and cartoon so the
# gallery view renders without additional round trips.
# ================================================================================

import base64
import datetime
import json
import os

import google.auth
import google.auth.transport.requests
from google.cloud import firestore, storage

MEDIA_BUCKET_NAME = os.environ["MEDIA_BUCKET_NAME"]
PRESIGNED_GET_TTL = 4 * 3600
PAGE_SIZE         = 50

_db = firestore.Client()


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


def _signed_get_url(
    client: storage.Client,
    blob_name: str,
    credentials,
    download_filename: str = None,
) -> str:
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


def history(request):
    if request.method == "OPTIONS":
        return ("", 204, _cors_headers())

    try:
        owner = _get_owner(request)
    except PermissionError as e:
        return _json(401, {"error": str(e)})

    # Fetch credentials once and reuse for all signed URLs in this response
    credentials, _ = google.auth.default()
    credentials.refresh(google.auth.transport.requests.Request())
    gcs_client = storage.Client(credentials=credentials)

    docs = (
        _db.collection("cartoonify_jobs")
        .where("owner", "==", owner)
        .order_by("created_at", direction=firestore.Query.DESCENDING)
        .limit(PAGE_SIZE)
        .stream()
    )

    items = []
    for doc in docs:
        item = doc.to_dict()
        entry = {
            "job_id":     item.get("job_id"),
            "status":     item.get("status"),
            "style":      item.get("style"),
            "created_at": item.get("created_at"),
        }
        if item.get("original_key"):
            entry["original_url"] = _signed_get_url(
                gcs_client, item["original_key"], credentials
            )
        if item.get("cartoon_key"):
            entry["cartoon_url"] = _signed_get_url(
                gcs_client,
                item["cartoon_key"],
                credentials,
                f"cartoonify-{item['job_id']}.png",
            )
        if item.get("error_message"):
            entry["error_message"] = item["error_message"]
        items.append(entry)

    return _json(200, {"items": items, "count": len(items)})
