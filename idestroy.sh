#!/usr/bin/env bash
set -euo pipefail

gcloud auth activate-service-account \
  "$(jq -r '.client_email' credentials.json)" \
  --key-file=credentials.json
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/credentials.json"

PROJECT=$(jq -r '.project_id' credentials.json)
echo "PROJECT: ${PROJECT}"

echo ""
echo "--- All composite indexes ---"
gcloud firestore indexes composite list --project="${PROJECT}"

echo ""
echo "--- Filtered to cartoonify_jobs (grep on name) ---"
gcloud firestore indexes composite list \
  --project="${PROJECT}" \
  --format="value(name)" 2>/dev/null \
  | grep "cartoonify_jobs" || echo "(none found)"

echo ""
echo "--- Deleting ---"
while IFS= read -r idx; do
  [ -z "${idx}" ] && continue
  echo "Deleting: ${idx}"
  gcloud firestore indexes composite delete "${idx}" \
    --project="${PROJECT}" --quiet
  echo "Deleted:  ${idx}"
done < <(gcloud firestore indexes composite list \
  --project="${PROJECT}" \
  --format="value(name)" 2>/dev/null \
  | grep "cartoonify_jobs")

echo ""
echo "--- Polling until gone ---"
while true; do
  REMAINING=$(gcloud firestore indexes composite list \
    --project="${PROJECT}" \
    --format="value(name)" 2>/dev/null \
    | grep "cartoonify_jobs" || true)
  echo "Still present: [${REMAINING}]"
  [ -z "${REMAINING}" ] && break
  sleep 5
done

echo ""
echo "Done — all cartoonify_jobs indexes gone."
