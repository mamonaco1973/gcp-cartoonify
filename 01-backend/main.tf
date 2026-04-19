terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

locals {
  credentials = jsondecode(file("${path.module}/../credentials.json"))
}

provider "google" {
  credentials = file("${path.module}/../credentials.json")
  project     = local.credentials.project_id
  region      = "us-central1"
}

provider "google-beta" {
  credentials = file("${path.module}/../credentials.json")
  project     = local.credentials.project_id
  region      = "us-central1"
}

# ================================================================================
# Random suffix — ensures globally unique bucket/key names
# ================================================================================

resource "random_id" "suffix" {
  byte_length = 4
}

# ================================================================================
# Service Accounts
# ================================================================================

# Handles HTTP functions: signs GCS URLs, publishes to Pub/Sub, reads Firestore
resource "google_service_account" "api_sa" {
  account_id   = "cartoonify-api-sa"
  display_name = "Cartoonify API Service Account"
}

# Handles async worker: consumes Pub/Sub, calls Vertex AI, writes GCS + Firestore
resource "google_service_account" "worker_sa" {
  account_id   = "cartoonify-worker-sa"
  display_name = "Cartoonify Worker Service Account"
}

# ================================================================================
# IAM: API SA
# ================================================================================

resource "google_project_iam_member" "api_pubsub_publisher" {
  project = local.credentials.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_project_iam_member" "api_firestore" {
  project = local.credentials.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.api_sa.email}"
}

# Self-impersonation for signing GCS V4 URLs without a key file
resource "google_service_account_iam_member" "api_sa_token_creator" {
  service_account_id = google_service_account.api_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_storage_bucket_iam_member" "api_media_object_viewer" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.api_sa.email}"
}

resource "google_storage_bucket_iam_member" "api_media_object_creator" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.api_sa.email}"
}

# ================================================================================
# IAM: Worker SA
# ================================================================================

resource "google_project_iam_member" "worker_pubsub_subscriber" {
  project = local.credentials.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.worker_sa.email}"
}

resource "google_project_iam_member" "worker_firestore" {
  project = local.credentials.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.worker_sa.email}"
}

# Vertex AI Imagen access
resource "google_project_iam_member" "worker_vertex_ai" {
  project = local.credentials.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.worker_sa.email}"
}

# Full object management on media bucket — reads originals, writes cartoons
resource "google_storage_bucket_iam_member" "worker_media_admin" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.worker_sa.email}"
}

# ================================================================================
# Outputs
# ================================================================================

output "api_sa_email" {
  value = google_service_account.api_sa.email
}

output "worker_sa_email" {
  value = google_service_account.worker_sa.email
}

output "media_bucket_name" {
  value = google_storage_bucket.media.name
}
