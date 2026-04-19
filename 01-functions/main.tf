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
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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

# ─── Service Account ────────────────────────────────────────────────────────────

resource "google_service_account" "notes_sa" {
  account_id   = "notes-sa"
  display_name = "Notes API Service Account"
}

resource "google_project_iam_member" "notes_firestore" {
  project = local.credentials.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.notes_sa.email}"
}

# ─── Source Code Storage ─────────────────────────────────────────────────────────

resource "random_id" "src_suffix" {
  byte_length = 4
}

resource "google_storage_bucket" "source" {
  name                        = "notes-src-${random_id.src_suffix.hex}"
  location                    = "US"
  force_destroy               = true
  uniform_bucket_level_access = true
}

data "archive_file" "notes_zip" {
  type        = "zip"
  source_dir  = "${path.module}/notes"
  output_path = "${path.module}/notes.zip"
}

resource "google_storage_bucket_object" "notes_zip" {
  name   = "notes-${data.archive_file.notes_zip.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.notes_zip.output_path
}

# ─── Cloud Function ─────────────────────────────────────────────────────────────

resource "google_cloudfunctions2_function" "notes" {
  name     = "notes"
  location = "us-central1"

  build_config {
    runtime     = "python311"
    entry_point = "notes"

    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.notes_zip.name
      }
    }
  }

  service_config {
    service_account_email = google_service_account.notes_sa.email
    timeout_seconds       = 60

    environment_variables = {
      GOOGLE_CLOUD_PROJECT = local.credentials.project_id
      CORS_ALLOW_ORIGIN    = "*"
    }
  }
}

output "notes_uri" {
  value = google_cloudfunctions2_function.notes.service_config[0].uri
}
