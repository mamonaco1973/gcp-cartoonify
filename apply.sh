#!/usr/bin/env bash
# ==============================================================================
# apply.sh
# ==============================================================================
# Orchestrates a three-phase Terraform deployment:
#   01-backend  : GCS media bucket, Pub/Sub, service accounts, IAM,
#                 Identity Platform API key, Firestore indexes
#   02-functions: 6 Cloud Functions (5 HTTP + 1 Pub/Sub worker) + API Gateway
#   03-webapp   : Public GCS web bucket + cartoonify SPA
#
# Requires: gcloud, terraform, jq in PATH + credentials.json in repo root
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Phase 0: Environment validation + API enablement
# ------------------------------------------------------------------------------
# shellcheck source=imagen-config.sh
source "$(dirname "$0")/imagen-config.sh"
./check_env.sh

project_id=$(jq -r '.project_id' credentials.json)

# ==============================================================================
# PHASE 1 — Backend (GCS, Pub/Sub, IAM, Identity Platform, Firestore)
# ==============================================================================
echo "NOTE: Phase 1 — provisioning backend resources..."

cd 01-backend
terraform init -input=false
terraform apply -auto-approve

MEDIA_BUCKET=$(terraform output -raw media_bucket_name)
FIREBASE_API_KEY=$(terraform output -raw firebase_api_key)
cd ..

echo "NOTE: media_bucket     = ${MEDIA_BUCKET}"
echo "NOTE: firebase_api_key ready"

# ==============================================================================
# PHASE 2 — Cloud Functions + API Gateway
# ==============================================================================
echo "NOTE: Phase 2 — deploying Cloud Functions and API Gateway..."

cd 02-functions
terraform init -input=false
terraform apply -auto-approve \
  -var="media_bucket_name=${MEDIA_BUCKET}" \
  -var="imagen_model_id=${IMAGEN_MODEL_ID}" \
  -var="gemini_model_id=${GEMINI_MODEL_ID}"

GATEWAY_URL=$(terraform output -raw gateway_url)
cd ..

echo "NOTE: gateway_url      = ${GATEWAY_URL}"

# ==============================================================================
# PHASE 3 — Web Application
# ==============================================================================
echo "NOTE: Phase 3 — building and deploying web application..."

cd 03-webapp

# Generate config.json loaded at runtime by the SPA
cat > config.json <<EOF
{
  "apiKey":      "${FIREBASE_API_KEY}",
  "authDomain":  "${project_id}.firebaseapp.com",
  "projectId":   "${project_id}",
  "apiBaseUrl":  "${GATEWAY_URL}"
}
EOF

# index.html has no template substitutions — Firebase config loads from config.json
cp index.html.tmpl index.html

terraform init -input=false
terraform apply -auto-approve
cd ..

# ==============================================================================
# Post-deploy summary
# ==============================================================================
./validate.sh
