# ─── Gateway Service Account ─────────────────────────────────────────────────

resource "google_service_account" "gateway_sa" {
  account_id   = "notes-gateway-sa"
  display_name = "Notes API Gateway Service Account"
}

# Allow the gateway SA to invoke the Cloud Function (Cloud Run service).
# The Cloud Function has no allUsers invoker — only this SA can reach it.
resource "google_cloud_run_service_iam_member" "gateway_invoker" {
  location = google_cloudfunctions2_function.notes.location
  service  = google_cloudfunctions2_function.notes.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.gateway_sa.email}"
}

# ─── API Gateway ─────────────────────────────────────────────────────────────

resource "google_api_gateway_api" "notes" {
  provider = google-beta
  project  = local.credentials.project_id
  api_id   = "notes-api"
}

resource "google_api_gateway_api_config" "notes" {
  provider      = google-beta
  project       = local.credentials.project_id
  api           = google_api_gateway_api.notes.api_id
  api_config_id = "notes-config-${random_id.src_suffix.hex}"

  # Use the gateway SA to generate OIDC tokens for Cloud Run backend auth.
  gateway_config {
    backend_config {
      google_service_account = google_service_account.gateway_sa.email
    }
  }

  openapi_documents {
    document {
      path = "openapi.yaml"
      contents = base64encode(templatefile("${path.module}/openapi.yaml.tpl", {
        project_id   = local.credentials.project_id
        function_uri = google_cloudfunctions2_function.notes.service_config[0].uri
      }))
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_cloud_run_service_iam_member.gateway_invoker]
}

resource "google_api_gateway_gateway" "notes" {
  provider   = google-beta
  project    = local.credentials.project_id
  region     = "us-central1"
  api_config = google_api_gateway_api_config.notes.id
  gateway_id = "notes-gateway"
}

output "gateway_url" {
  value = "https://${google_api_gateway_gateway.notes.default_hostname}"
}
