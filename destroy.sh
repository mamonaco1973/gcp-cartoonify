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

# Firestore index deletion is async — capture our index names first, delete
# them, then poll only for those until GCP confirms they are gone.
# Polling the full list never exits because system indexes always remain.
PROJECT=$(jq -r '.project_id' credentials.json)
echo "NOTE: Deleting Firestore composite indexes..."
OUR_INDEXES=$(gcloud firestore indexes composite list \
    --project="${PROJECT}" \
    --format="value(name)" 2>/dev/null \
    | grep "cartoonify_jobs" || true)

for idx in ${OUR_INDEXES}; do
  gcloud firestore indexes composite delete "${idx}" \
    --project="${PROJECT}" --quiet 2>/dev/null || true
done

if [ -n "${OUR_INDEXES}" ]; then
  echo "NOTE: Waiting for Firestore index deletion to complete..."
  until ! gcloud firestore indexes composite list \
      --project="${PROJECT}" \
      --format="value(name)" 2>/dev/null \
      | grep -q "cartoonify_jobs"; do
    sleep 5
  done
fi

echo "NOTE: Destroying backend resources..."
cd 01-backend
terraform destroy -auto-approve
cd ..

echo "NOTE: Destroy complete."
