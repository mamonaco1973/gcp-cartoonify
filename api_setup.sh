#!/usr/bin/env bash
set -euo pipefail

if [ ! -f credentials.json ]; then
  echo "ERROR: credentials.json not found in repo root."
  exit 1
fi

project_id=$(jq -r '.project_id' credentials.json)
client_email=$(jq -r '.client_email' credentials.json)

echo "NOTE: Authenticating with GCP project: ${project_id}"
gcloud auth activate-service-account "${client_email}" --key-file=credentials.json
gcloud config set project "${project_id}"

echo "NOTE: Enabling required GCP APIs..."
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  compute.googleapis.com \
  storage.googleapis.com \
  firestore.googleapis.com \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  eventarc.googleapis.com \
  artifactregistry.googleapis.com \
  identitytoolkit.googleapis.com \
  apigateway.googleapis.com \
  servicemanagement.googleapis.com \
  servicecontrol.googleapis.com \
  apikeys.googleapis.com \
  aiplatform.googleapis.com \
  pubsub.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com

echo "NOTE: Enabling Identity Platform email/password sign-in..."
access_token=$(gcloud auth print-access-token)
curl -sf -X PATCH \
  "https://identitytoolkit.googleapis.com/v2/projects/${project_id}/config?updateMask=signIn.email.enabled,signIn.email.passwordRequired" \
  -H "Authorization: Bearer ${access_token}" \
  -H "Content-Type: application/json" \
  -H "X-Goog-User-Project: ${project_id}" \
  -d '{"signIn":{"email":{"enabled":true,"passwordRequired":true}}}' \
  > /dev/null
echo "NOTE: Identity Platform configured."

echo "NOTE: Ensuring Firestore database exists in native mode..."
gcloud firestore databases create \
  --location=us-central1 \
  --type=firestore-native \
  --database="(default)" 2>/dev/null \
  || echo "NOTE: Firestore database already exists."

echo "NOTE: Creating Firestore composite indexes (idempotent)..."
# history: owner == uid ORDER BY created_at DESC
gcloud firestore indexes composite create \
  --project="${project_id}" \
  --collection-group=cartoonify_jobs \
  --field-config="field-path=owner,order=ascending" \
  --field-config="field-path=created_at,order=descending" \
  --quiet 2>/dev/null \
  || echo "NOTE: history index already exists."

# quota: owner == uid AND created_at >= today_start
gcloud firestore indexes composite create \
  --project="${project_id}" \
  --collection-group=cartoonify_jobs \
  --field-config="field-path=owner,order=ascending" \
  --field-config="field-path=created_at,order=ascending" \
  --quiet 2>/dev/null \
  || echo "NOTE: quota index already exists."

echo "NOTE: API setup complete."
