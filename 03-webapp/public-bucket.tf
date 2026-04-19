# ================================================================================
# GCS: Public static web hosting bucket
# ================================================================================

resource "random_id" "suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "webapp" {
  name                        = "cartoonify-web-${random_id.suffix.hex}"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = false

  website {
    main_page_suffix = "index.html"
  }
}

resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.webapp.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_object" "index_html" {
  name          = "index.html"
  bucket        = google_storage_bucket.webapp.name
  source        = "${path.module}/index.html"
  content_type  = "text/html"
  cache_control = "no-store, no-cache, must-revalidate, max-age=0"
}

resource "google_storage_bucket_object" "config_json" {
  name          = "config.json"
  bucket        = google_storage_bucket.webapp.name
  source        = "${path.module}/config.json"
  content_type  = "application/json"
  cache_control = "no-store, no-cache, must-revalidate, max-age=0"
}

resource "google_storage_bucket_object" "favicon" {
  name         = "favicon.ico"
  bucket       = google_storage_bucket.webapp.name
  source       = "${path.module}/favicon.ico"
  content_type = "image/x-icon"
}

output "webapp_url" {
  value = "https://storage.googleapis.com/${google_storage_bucket.webapp.name}/index.html"
}
