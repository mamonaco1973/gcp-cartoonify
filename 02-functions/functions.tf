# ================================================================================
# Gateway Service Account
# ================================================================================
# The API Gateway uses this SA to generate OIDC tokens for Cloud Run backend
# auth. HTTP functions are private — only the gateway SA can invoke them.
# ================================================================================

resource "google_service_account" "gateway_sa" {
  account_id   = "cartoonify-gateway-sa"
  display_name = "Cartoonify API Gateway Service Account"
}

# ================================================================================
# HTTP Cloud Functions (5 API handlers)
# ================================================================================

resource "google_cloudfunctions2_function" "upload_url" {
  name     = "cartoonify-upload-url"
  location = "us-central1"

  build_config {
    runtime     = "python311"
    entry_point = "upload_url"
    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.upload_url_obj.name
      }
    }
  }

  service_config {
    service_account_email = data.google_service_account.api_sa.email
    timeout_seconds       = 60
    environment_variables = {
      GOOGLE_CLOUD_PROJECT = local.credentials.project_id
      MEDIA_BUCKET_NAME    = var.media_bucket_name
      CORS_ALLOW_ORIGIN    = "*"
    }
  }
}

resource "google_cloudfunctions2_function" "submit" {
  name     = "cartoonify-submit"
  location = "us-central1"

  build_config {
    runtime     = "python311"
    entry_point = "submit"
    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.submit_obj.name
      }
    }
  }

  service_config {
    service_account_email = data.google_service_account.api_sa.email
    timeout_seconds       = 60
    environment_variables = {
      GOOGLE_CLOUD_PROJECT = local.credentials.project_id
      MEDIA_BUCKET_NAME    = var.media_bucket_name
      JOBS_TOPIC           = "cartoonify-jobs"
      CORS_ALLOW_ORIGIN    = "*"
    }
  }
}

resource "google_cloudfunctions2_function" "result" {
  name     = "cartoonify-result"
  location = "us-central1"

  build_config {
    runtime     = "python311"
    entry_point = "result"
    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.result_obj.name
      }
    }
  }

  service_config {
    service_account_email = data.google_service_account.api_sa.email
    timeout_seconds       = 60
    environment_variables = {
      GOOGLE_CLOUD_PROJECT = local.credentials.project_id
      MEDIA_BUCKET_NAME    = var.media_bucket_name
      CORS_ALLOW_ORIGIN    = "*"
    }
  }
}

resource "google_cloudfunctions2_function" "history" {
  name     = "cartoonify-history"
  location = "us-central1"

  build_config {
    runtime     = "python311"
    entry_point = "history"
    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.history_obj.name
      }
    }
  }

  service_config {
    service_account_email = data.google_service_account.api_sa.email
    timeout_seconds       = 60
    environment_variables = {
      GOOGLE_CLOUD_PROJECT = local.credentials.project_id
      MEDIA_BUCKET_NAME    = var.media_bucket_name
      CORS_ALLOW_ORIGIN    = "*"
    }
  }
}

resource "google_cloudfunctions2_function" "delete" {
  name     = "cartoonify-delete"
  location = "us-central1"

  build_config {
    runtime     = "python311"
    entry_point = "delete_job"
    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.delete_obj.name
      }
    }
  }

  service_config {
    service_account_email = data.google_service_account.api_sa.email
    timeout_seconds       = 60
    environment_variables = {
      GOOGLE_CLOUD_PROJECT = local.credentials.project_id
      MEDIA_BUCKET_NAME    = var.media_bucket_name
      CORS_ALLOW_ORIGIN    = "*"
    }
  }
}

# ================================================================================
# Pub/Sub-triggered worker Cloud Function
# ================================================================================
# Uses Eventarc to receive messagePublished events from the cartoonify-jobs topic.
# 512 MB memory and 300s timeout accommodate Vertex AI Imagen inference.
# ================================================================================

resource "google_cloudfunctions2_function" "worker" {
  name     = "cartoonify-worker"
  location = "us-central1"

  build_config {
    runtime     = "python311"
    entry_point = "cartoonify_worker"
    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.worker_obj.name
      }
    }
  }

  service_config {
    service_account_email = data.google_service_account.worker_sa.email
    timeout_seconds       = 300
    available_memory      = "512M"
    environment_variables = {
      GOOGLE_CLOUD_PROJECT = local.credentials.project_id
      MEDIA_BUCKET_NAME    = var.media_bucket_name
    }
  }

  event_trigger {
    event_type   = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = data.google_pubsub_topic.jobs.id
    retry_policy = "RETRY_POLICY_RETRY"
  }
}

# ================================================================================
# Cloud Run IAM: gateway SA can invoke each private HTTP function
# ================================================================================

resource "google_cloud_run_service_iam_member" "gateway_upload_url" {
  location = google_cloudfunctions2_function.upload_url.location
  service  = google_cloudfunctions2_function.upload_url.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.gateway_sa.email}"
}

resource "google_cloud_run_service_iam_member" "gateway_submit" {
  location = google_cloudfunctions2_function.submit.location
  service  = google_cloudfunctions2_function.submit.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.gateway_sa.email}"
}

resource "google_cloud_run_service_iam_member" "gateway_result" {
  location = google_cloudfunctions2_function.result.location
  service  = google_cloudfunctions2_function.result.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.gateway_sa.email}"
}

resource "google_cloud_run_service_iam_member" "gateway_history" {
  location = google_cloudfunctions2_function.history.location
  service  = google_cloudfunctions2_function.history.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.gateway_sa.email}"
}

resource "google_cloud_run_service_iam_member" "gateway_delete" {
  location = google_cloudfunctions2_function.delete.location
  service  = google_cloudfunctions2_function.delete.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.gateway_sa.email}"
}

# ================================================================================
# API Gateway
# ================================================================================
# Routes each path to its dedicated Cloud Function.
# Firebase JWT auth is validated at the gateway level before any function runs.
# ================================================================================

resource "google_api_gateway_api" "cartoonify" {
  provider = google-beta
  project  = local.credentials.project_id
  api_id   = "cartoonify-api"
}

resource "google_api_gateway_api_config" "cartoonify" {
  provider      = google-beta
  project       = local.credentials.project_id
  api           = google_api_gateway_api.cartoonify.api_id
  api_config_id = "cartoonify-config-${random_string.src_suffix.result}"

  gateway_config {
    backend_config {
      google_service_account = google_service_account.gateway_sa.email
    }
  }

  openapi_documents {
    document {
      path = "openapi.yaml"
      contents = base64encode(templatefile("${path.module}/openapi.yaml.tpl", {
        project_id     = local.credentials.project_id
        upload_url_uri = google_cloudfunctions2_function.upload_url.service_config[0].uri
        submit_uri     = google_cloudfunctions2_function.submit.service_config[0].uri
        result_uri     = google_cloudfunctions2_function.result.service_config[0].uri
        history_uri    = google_cloudfunctions2_function.history.service_config[0].uri
        delete_uri     = google_cloudfunctions2_function.delete.service_config[0].uri
      }))
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    google_cloud_run_service_iam_member.gateway_upload_url,
    google_cloud_run_service_iam_member.gateway_submit,
    google_cloud_run_service_iam_member.gateway_result,
    google_cloud_run_service_iam_member.gateway_history,
    google_cloud_run_service_iam_member.gateway_delete,
  ]
}

resource "google_api_gateway_gateway" "cartoonify" {
  provider   = google-beta
  project    = local.credentials.project_id
  region     = "us-central1"
  api_config = google_api_gateway_api_config.cartoonify.id
  gateway_id = "cartoonify-gateway"
}

output "gateway_url" {
  value = "https://${google_api_gateway_gateway.cartoonify.default_hostname}"
}
