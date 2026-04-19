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
# Archive each function directory into a zip
# MD5-tagged names cause Terraform to re-upload only when code changes.
# ================================================================================

data "archive_file" "upload_url_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/upload_url"
  output_path = "${path.module}/code/upload_url.zip"
}

data "archive_file" "submit_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/submit"
  output_path = "${path.module}/code/submit.zip"
}

data "archive_file" "result_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/result"
  output_path = "${path.module}/code/result.zip"
}

data "archive_file" "history_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/history"
  output_path = "${path.module}/code/history.zip"
}

data "archive_file" "delete_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/delete"
  output_path = "${path.module}/code/delete.zip"
}

data "archive_file" "worker_zip" {
  type        = "zip"
  source_dir  = "${path.module}/code/worker"
  output_path = "${path.module}/code/worker.zip"
}

# ================================================================================
# Upload archives to source bucket
# ================================================================================

resource "google_storage_bucket_object" "upload_url_obj" {
  name   = "upload_url-${data.archive_file.upload_url_zip.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.upload_url_zip.output_path
}

resource "google_storage_bucket_object" "submit_obj" {
  name   = "submit-${data.archive_file.submit_zip.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.submit_zip.output_path
}

resource "google_storage_bucket_object" "result_obj" {
  name   = "result-${data.archive_file.result_zip.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.result_zip.output_path
}

resource "google_storage_bucket_object" "history_obj" {
  name   = "history-${data.archive_file.history_zip.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.history_zip.output_path
}

resource "google_storage_bucket_object" "delete_obj" {
  name   = "delete-${data.archive_file.delete_zip.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.delete_zip.output_path
}

resource "google_storage_bucket_object" "worker_obj" {
  name   = "worker-${data.archive_file.worker_zip.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.worker_zip.output_path
}
