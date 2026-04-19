"""
notes/main.py — Cloud Function entry point for the Notes CRUD API.

This module implements a single Cloud Functions 2nd Gen HTTP function (`notes`)
that handles all five REST operations for a note-taking application.  A single
function inspects `request.method` and `request.path` to dispatch internally.

Routing table:
    POST   /notes          → _create(request, owner)
    GET    /notes          → _list(owner)
    GET    /notes/{id}     → _get(note_id, owner)
    PUT    /notes/{id}     → _update(request, note_id, owner)
    DELETE /notes/{id}     → _delete(note_id, owner)
    OPTIONS *              → CORS preflight (204 No Content)

Authentication:
    Requests arrive via Cloud API Gateway, which validates the Firebase
    ID token (issued by Identity Platform) and passes decoded JWT claims
    to the function in the X-Apigateway-Api-Userinfo header (base64url JSON).
    The function extracts the `sub` claim (Firebase UID) as the owner key.
    The Cloud Function itself is NOT publicly accessible — only the API
    Gateway service account has roles/run.invoker.

Path routing:
    Because requests come from Cloud API Gateway using APPEND_PATH_TO_ADDRESS,
    the Cloud Run service receives the full path:
        request.path = "/notes"       → collection operation
        request.path = "/notes/{id}"  → item operation

Storage:
    Firestore (Native mode), collection "notes", document key UUID4.
    All queries are scoped to the authenticated owner (Firebase UID).

Environment variables:
    CORS_ALLOW_ORIGIN   Value of Access-Control-Allow-Origin. Defaults to "*".
"""

import base64
import json
import os
import uuid
from datetime import datetime, timezone

from google.cloud import firestore

# ---------------------------------------------------------------------------
# Module-level singletons
# ---------------------------------------------------------------------------

db = firestore.Client()
COLLECTION = "notes"
CORS_ORIGIN = os.environ.get("CORS_ALLOW_ORIGIN", "*")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _cors_headers():
    """Return CORS headers. Authorization is included so the SPA can send tokens."""
    return {
        "Access-Control-Allow-Origin": CORS_ORIGIN,
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
    }


def _json(data, status=200):
    """Serialise data to JSON and return a Cloud Functions response tuple."""
    return (json.dumps(data), status, {**_cors_headers(), "Content-Type": "application/json"})


def _get_owner(request):
    """Extract the authenticated Firebase UID from the API Gateway header.

    Cloud API Gateway validates the Firebase ID token and base64url-encodes
    the decoded JWT claims into the X-Apigateway-Api-Userinfo request header.
    The Firebase UID is in the `sub` claim.

    Returns:
        str: The Firebase UID, or None if the header is absent or malformed.
    """
    userinfo = request.headers.get("X-Apigateway-Api-Userinfo")
    if not userinfo:
        return None
    try:
        # base64url may lack padding; restore it before decoding.
        padding = 4 - len(userinfo) % 4
        if padding != 4:
            userinfo += "=" * padding
        claims = json.loads(base64.urlsafe_b64decode(userinfo))
        return claims.get("sub") or claims.get("user_id")
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def notes(request):
    """Cloud Function entry point — routes incoming HTTP requests to handlers.

    Path format received from API Gateway (APPEND_PATH_TO_ADDRESS):
        request.path = "/notes"       → collection operations
        request.path = "/notes/{id}"  → item operations

    Args:
        request (flask.Request): The incoming HTTP request.

    Returns:
        tuple: (body, status_code, headers)
    """
    if request.method == "OPTIONS":
        return ("", 204, _cors_headers())

    # Extract note ID from path: /notes → None, /notes/{id} → "{id}"
    parts = request.path.rstrip("/").split("/")
    note_id = parts[2] if len(parts) > 2 else None

    owner = _get_owner(request)
    if owner is None:
        return _json({"error": "Unauthorized"}, 401)

    if request.method == "POST" and note_id is None:
        return _create(request, owner)
    if request.method == "GET" and note_id is None:
        return _list(owner)
    if request.method == "GET" and note_id:
        return _get(note_id, owner)
    if request.method == "PUT" and note_id:
        return _update(request, note_id, owner)
    if request.method == "DELETE" and note_id:
        return _delete(note_id, owner)

    return _json({"error": "Not found"}, 404)


# ---------------------------------------------------------------------------
# CRUD handlers
# ---------------------------------------------------------------------------

def _create(request, owner):
    """Create a new note owned by the authenticated user.

    Args:
        request (flask.Request): Must contain JSON body with title and note.
        owner (str): Firebase UID of the authenticated user.

    Returns:
        tuple: 201 with {id, title, note} on success; 400 or 500 on error.
    """
    try:
        body = request.get_json(silent=True) or {}
        title = body.get("title", "").strip()
        note = body.get("note", "").strip()

        if not title or not note:
            return _json({"error": "title and note are required"}, 400)

        note_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()

        item = {
            "owner":      owner,
            "id":         note_id,
            "title":      title,
            "note":       note,
            "created_at": now,
            "updated_at": now,
        }

        db.collection(COLLECTION).document(note_id).set(item)
        return _json({"id": note_id, "title": title, "note": note}, 201)

    except Exception as e:
        return _json({"error": str(e)}, 500)


def _list(owner):
    """List all notes belonging to the authenticated user.

    Args:
        owner (str): Firebase UID used as the Firestore filter value.

    Returns:
        tuple: 200 with {items: [...]} on success; 500 on error.
    """
    try:
        docs = db.collection(COLLECTION).where("owner", "==", owner).stream()
        items = [doc.to_dict() for doc in docs]
        return _json({"items": items})

    except Exception as e:
        return _json({"error": str(e)}, 500)


def _get(note_id, owner):
    """Retrieve a single note, verifying it belongs to the authenticated user.

    Args:
        note_id (str): UUID4 document ID from the request path.
        owner (str): Firebase UID — must match the note's owner field.

    Returns:
        tuple: 200 with the note dict; 404 if not found or not owned; 500 on error.
    """
    try:
        doc = db.collection(COLLECTION).document(note_id).get()

        if not doc.exists:
            return _json({"error": "Note not found"}, 404)

        data = doc.to_dict()
        # Return 404 (not 403) to avoid leaking existence of other users' notes.
        if data.get("owner") != owner:
            return _json({"error": "Note not found"}, 404)

        return _json(data)

    except Exception as e:
        return _json({"error": str(e)}, 500)


def _update(request, note_id, owner):
    """Update a note's title and body, verifying ownership first.

    Args:
        request (flask.Request): JSON body with title and note.
        note_id (str): UUID4 document ID from the request path.
        owner (str): Firebase UID — must match the note's owner field.

    Returns:
        tuple: 200 with the updated note; 400/404/500 on error.
    """
    try:
        body = request.get_json(silent=True) or {}
        title = body.get("title", "").strip()
        note = body.get("note", "").strip()

        if not title or not note:
            return _json({"error": "title and note are required"}, 400)

        ref = db.collection(COLLECTION).document(note_id)
        doc = ref.get()

        if not doc.exists:
            return _json({"error": "Note not found"}, 404)

        if doc.to_dict().get("owner") != owner:
            return _json({"error": "Note not found"}, 404)

        now = datetime.now(timezone.utc).isoformat()
        ref.update({"title": title, "note": note, "updated_at": now})

        return _json(ref.get().to_dict())

    except Exception as e:
        return _json({"error": str(e)}, 500)


def _delete(note_id, owner):
    """Delete a note, verifying it belongs to the authenticated user.

    Args:
        note_id (str): UUID4 document ID from the request path.
        owner (str): Firebase UID — must match the note's owner field.

    Returns:
        tuple: 200 with {message: "Note deleted"}; 404/500 on error.
    """
    try:
        ref = db.collection(COLLECTION).document(note_id)
        doc = ref.get()

        if not doc.exists:
            return _json({"error": "Note not found"}, 404)

        if doc.to_dict().get("owner") != owner:
            return _json({"error": "Note not found"}, 404)

        ref.delete()
        return _json({"message": "Note deleted"})

    except Exception as e:
        return _json({"error": str(e)}, 500)
