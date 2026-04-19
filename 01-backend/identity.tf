# Identity Platform is enabled via api_setup.sh (REST API).
# It cannot be disabled once active, so it is intentionally not managed here.

# ================================================================================
# Browser API Key
# ================================================================================
# Scoped to Identity Platform only — safe to embed in the SPA.

resource "random_id" "apikey_suffix" {
  byte_length = 3
}

resource "google_apikeys_key" "webapp" {
  name         = "cartoonify-webapp-key-${random_id.apikey_suffix.hex}"
  display_name = "Cartoonify Web App API Key"
  project      = local.credentials.project_id

  restrictions {
    api_targets {
      service = "identitytoolkit.googleapis.com"
    }
  }
}

output "firebase_api_key" {
  value     = google_apikeys_key.webapp.key_string
  sensitive = true
}
