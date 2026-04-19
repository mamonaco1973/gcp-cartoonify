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

# ================================================================================
# Variables — passed in from apply.sh after 01-backend outputs
# ================================================================================

variable "media_bucket_name" {
  description = "Name of the private GCS media bucket (from 01-backend output)"
  type        = string
}

# ================================================================================
# Data sources — resolve service accounts created in 01-backend
# ================================================================================

data "google_service_account" "api_sa" {
  account_id = "cartoonify-api-sa"
}

data "google_service_account" "worker_sa" {
  account_id = "cartoonify-worker-sa"
}

data "google_pubsub_topic" "jobs" {
  name = "cartoonify-jobs"
}

# ================================================================================
# Random suffix for source bucket name
# ================================================================================

resource "random_string" "src_suffix" {
  length  = 6
  upper   = false
  special = false
}

# ================================================================================
# GCS bucket for function source archives
# ================================================================================

resource "google_storage_bucket" "source" {
  name          = "cartoonify-src-${random_string.src_suffix.result}"
  location      = "US"
  storage_class = "STANDARD"
  force_destroy = true
}

# ================================================================================
# Archive function source directories into zips.
# MD5-tagged names cause Terraform to re-upload only when code changes.
# ================================================================================

data "archive_file" "api_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/api"
  output_path = "${path.module}/code/api.zip"
}

data "archive_file" "worker_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/worker"
  output_path = "${path.module}/code/worker.zip"
}

# ================================================================================
# Upload archives to source bucket
# ================================================================================

resource "google_storage_bucket_object" "api_obj" {
  name   = "api-${data.archive_file.api_zip.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.api_zip.output_path
}

resource "google_storage_bucket_object" "worker_obj" {
  name   = "worker-${data.archive_file.worker_zip.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.worker_zip.output_path
}
