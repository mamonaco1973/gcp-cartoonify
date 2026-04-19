terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
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
