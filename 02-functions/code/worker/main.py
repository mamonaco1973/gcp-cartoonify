# ================================================================================
# cartoonify_worker — Pub/Sub-triggered worker
# ================================================================================
# Triggered by Eventarc on each message published to cartoonify-jobs.
# For each message:
#   1. Download the uploaded original image from GCS
#   2. Normalize: EXIF strip, center-square-crop, resize to 1024×1024 PNG
#   3. Call Vertex AI Imagen imagen-3.0-capability-001 edit_image with style prompt
#   4. Upload the generated cartoon PNG to GCS under cartoons/<owner>/<job_id>.png
#   5. Update the Firestore job document to status=complete (or status=error)
#
# Pub/Sub message shape (produced by submit function):
#   {
#     "job_id":       "<ms>-<hex>",
#     "owner":        "<firebase uid>",
#     "style":        "<style id>",
#     "original_key": "originals/<owner>/<job_id>.<ext>",
#     "prompt_extra": ""
#   }
# ================================================================================

import base64
import io
import json
import logging
import os
import time

import vertexai
from vertexai.preview.vision_models import ImageGenerationModel
from vertexai.preview.vision_models import Image as VertexImage
from google.cloud import firestore, storage
from PIL import Image, ImageOps

PROJECT_ID        = os.environ["GOOGLE_CLOUD_PROJECT"]
MEDIA_BUCKET_NAME = os.environ["MEDIA_BUCKET_NAME"]
IMAGEN_MODEL_ID   = os.environ["IMAGEN_MODEL_ID"]

TARGET_SIZE = 1024

# Style prompts. Keys sent by the client; full text stays server-side.
STYLE_PROMPTS = {
    "pixar_3d": (
        "Pixar 3D animated portrait, subsurface skin shading, warm rim lighting, "
        "large expressive eyes, smooth stylized features, vibrant color grading, "
        "cinematic depth of field, high-quality render"
    ),
    "simpsons": (
        "The Simpsons animated style, bright yellow skin, bold black outlines, "
        "flat cel-shaded colors, D-shaped ears, overbite, Springfield cartoon aesthetic"
    ),
    "comic_book": (
        "Marvel comic book illustration, Ben-Day dot shading, bold ink outlines, "
        "dramatic shadows, saturated primary colors, dynamic superhero rendering"
    ),
    "anime": (
        "Japanese anime portrait, detailed cel-shading, vibrant hair, large luminous eyes, "
        "clean sharp lineart, soft highlight gloss, manga-style rendering"
    ),
    "watercolor": (
        "fine art watercolor portrait, loose wet-on-wet washes, soft color blooms, "
        "visible paper texture, delicate brushwork, impressionist light"
    ),
    "pencil_sketch": (
        "detailed graphite portrait sketch, cross-hatching, tonal shading, "
        "textured paper grain, charcoal smudge, monochrome rendering, artist sketchbook"
    ),
}

# Module-scoped clients — reused across warm invocations
_db  = firestore.Client()
_gcs = storage.Client()

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _prepare_image(src_bytes: bytes) -> bytes:
    """Normalize to a center-square-cropped 1024×1024 PNG."""
    img = Image.open(io.BytesIO(src_bytes))
    img = ImageOps.exif_transpose(img)
    img = img.convert("RGB")

    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top  = (h - side) // 2
    img  = img.crop((left, top, left + side, top + side))
    img  = img.resize((TARGET_SIZE, TARGET_SIZE), Image.LANCZOS)

    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def _invoke_imagen(prepared_bytes: bytes, style_id: str, prompt_extra: str) -> bytes:
    """Call Vertex AI Imagen edit_image and return generated PNG bytes."""
    prompt = STYLE_PROMPTS.get(style_id)
    if not prompt:
        raise ValueError(f"Unknown style: {style_id!r}")
    if prompt_extra:
        prompt = f"{prompt}, {prompt_extra}"

    vertexai.init(project=PROJECT_ID, location="us-central1")
    model  = ImageGenerationModel.from_pretrained(IMAGEN_MODEL_ID)
    source = VertexImage(image_bytes=prepared_bytes)

    logger.info("Invoking Imagen model=%s style=%s", IMAGEN_MODEL_ID, style_id)
    result = model.edit_image(
        base_image=source,
        prompt=prompt,
        number_of_images=1,
    )

    if not result.images:
        raise RuntimeError("Imagen returned no images")

    return result.images[0]._image_bytes


def _process_message(msg: dict) -> None:
    job_id       = msg["job_id"]
    owner        = msg["owner"]
    style        = msg["style"]
    original_key = msg["original_key"]
    prompt_extra = msg.get("prompt_extra") or ""

    logger.info("Processing job=%s owner=%s style=%s key=%s",
                job_id, owner, style, original_key)

    doc_ref = _db.collection("cartoonify_jobs").document(job_id)
    doc_ref.update({"status": "processing"})

    bucket = _gcs.bucket(MEDIA_BUCKET_NAME)

    # 1. Download original from GCS
    src_bytes = bucket.blob(original_key).download_as_bytes()

    # 2. Normalize image
    prepared_bytes = _prepare_image(src_bytes)

    # 3. Generate cartoon via Vertex AI Imagen
    cartoon_bytes = _invoke_imagen(prepared_bytes, style, prompt_extra)

    # 4. Upload cartoon to GCS
    cartoon_key = f"cartoons/{owner}/{job_id}.png"
    bucket.blob(cartoon_key).upload_from_string(cartoon_bytes, content_type="image/png")

    # 5. Mark complete in Firestore
    doc_ref.update({
        "status":       "complete",
        "cartoon_key":  cartoon_key,
        "completed_at": int(time.time()),
    })
    logger.info("Completed job=%s → %s", job_id, cartoon_key)


def cartoonify_worker(event, context):
    """Pub/Sub-triggered entry point via Eventarc."""
    payload = base64.b64decode(event["data"]).decode("utf-8")
    msg     = json.loads(payload)

    try:
        _process_message(msg)
    except Exception as exc:
        logger.exception("Failed to process job: %s", exc)
        owner  = msg.get("owner")
        job_id = msg.get("job_id")
        if owner and job_id:
            try:
                _db.collection("cartoonify_jobs").document(job_id).update({
                    "status":        "error",
                    "error_message": str(exc)[:500],
                    "completed_at":  int(time.time()),
                })
            except Exception:
                logger.exception("Failed to mark job as error")
        # Swallow the exception — Pub/Sub retry is handled by the dead-letter
        # policy. The job document's status=error is the canonical failure signal.
