# ================================================================================
# GCS: Private media bucket
# ================================================================================
# Stores original uploads (originals/<owner>/<job_id>.<ext>) and
# generated cartoons (cartoons/<owner>/<job_id>.png). Access via
# V4 signed URLs issued by the API functions — no public access.
# ================================================================================

resource "google_storage_bucket" "media" {
  name                        = "cartoonify-media-${random_id.suffix.hex}"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true

  cors {
    origin          = ["*"]
    method          = ["GET", "PUT", "HEAD", "OPTIONS"]
    response_header = ["Content-Type", "Authorization", "x-goog-resumable"]
    max_age_seconds = 3600
  }

  # 7-day lifecycle — matches job TTL; keeps storage costs bounded
  lifecycle_rule {
    condition {
      age            = 7
      matches_prefix = ["originals/", "cartoons/"]
    }
    action {
      type = "Delete"
    }
  }
}
