# ================================================================================
# delete_job — DELETE /history/{job_id}
# ================================================================================
# Removes a single job document and its associated GCS objects (original +
# cartoon). Ownership is enforced — users may only delete their own jobs.
# ================================================================================

import base64
import json
import os

from google.cloud import firestore, storage

MEDIA_BUCKET_NAME = os.environ["MEDIA_BUCKET_NAME"]

_db  = firestore.Client()
_gcs = storage.Client()


def _cors_headers():
    origin = os.environ.get("CORS_ALLOW_ORIGIN", "*")
    return {
        "Access-Control-Allow-Origin":  origin,
        "Access-Control-Allow-Methods": "DELETE,OPTIONS",
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


def delete_job(request):
    if request.method == "OPTIONS":
        return ("", 204, _cors_headers())

    try:
        owner = _get_owner(request)
    except PermissionError as e:
        return _json(401, {"error": str(e)})

    job_id = request.path.rstrip("/").split("/")[-1]
    if not job_id:
        return _json(400, {"error": "Missing job_id"})

    doc_ref = _db.collection("cartoonify_jobs").document(job_id)
    doc     = doc_ref.get()
    if not doc.exists:
        return _json(404, {"error": "Not found"})

    item = doc.to_dict()

    # Enforce ownership
    if item.get("owner") != owner:
        return _json(404, {"error": "Not found"})

    # Delete GCS objects for this job
    bucket     = _gcs.bucket(MEDIA_BUCKET_NAME)
    keys_to_rm = [k for k in (item.get("original_key"), item.get("cartoon_key")) if k]
    for key in keys_to_rm:
        try:
            bucket.blob(key).delete()
        except Exception:
            pass  # best-effort; object may already be gone via lifecycle rule

    doc_ref.delete()

    return _json(200, {"job_id": job_id, "deleted": True})
