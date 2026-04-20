#!/usr/bin/env bash
# ==============================================================================
# destroy.sh — tear down in reverse phase order
# ==============================================================================

set -euo pipefail

# shellcheck source=imagen-config.sh
source "$(dirname "$0")/imagen-config.sh"

# Authenticate so gcloud and Terraform have credentials
gcloud auth activate-service-account \
  "$(jq -r '.client_email' credentials.json)" \
  --key-file=credentials.json
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/credentials.json"

MEDIA_BUCKET=$(cd 01-backend && terraform output -raw media_bucket_name 2>/dev/null || echo "")

# ==============================================================================
# PHASE 3 — Web Application
# ==============================================================================
echo "NOTE: Destroying web application..."
cd 03-webapp
terraform destroy -auto-approve || true
cd ..

# ==============================================================================
# PHASE 2 — Cloud Functions + API Gateway
# ==============================================================================
echo "NOTE: Destroying Cloud Functions and API Gateway..."
cd 02-functions
terraform destroy -auto-approve \
  -var="media_bucket_name=${MEDIA_BUCKET:-placeholder}" \
  -var="imagen_model_id=${IMAGEN_MODEL_ID}" || true
cd ..

# ==============================================================================
# PHASE 1 — Backend (empties media bucket first so GCS destroy succeeds)
# ==============================================================================
if [ -n "${MEDIA_BUCKET}" ]; then
  echo "NOTE: Emptying media bucket ${MEDIA_BUCKET}..."
  gcloud storage rm -r "gs://${MEDIA_BUCKET}/**" 2>/dev/null || true
fi

echo "NOTE: Deleting all cartoonify_jobs Firestore documents..."
FS_PROJECT=$(jq -r '.project_id' credentials.json)
FS_TOKEN=$(gcloud auth print-access-token)
FS_BASE="https://firestore.googleapis.com/v1/projects/${FS_PROJECT}/databases/(default)/documents"

while true; do
  DOC_NAMES=$(curl -sf \
    -H "Authorization: Bearer ${FS_TOKEN}" \
    "${FS_BASE}/cartoonify_jobs?pageSize=100" \
    | jq -r '.documents[]?.name // empty' 2>/dev/null || true)
  [ -z "${DOC_NAMES}" ] && break
  while IFS= read -r doc; do
    curl -sf -X DELETE \
      -H "Authorization: Bearer ${FS_TOKEN}" \
      "https://firestore.googleapis.com/v1/${doc}" > /dev/null || true
  done <<< "${DOC_NAMES}"
done

echo "NOTE: Destroying backend resources..."
cd 01-backend
terraform destroy -auto-approve
cd ..

echo "NOTE: Destroy complete."
