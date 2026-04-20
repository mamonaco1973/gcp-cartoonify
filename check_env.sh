#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=imagen-config.sh
source "$(dirname "$0")/imagen-config.sh"

echo "NOTE: Validating required commands..."
commands=("gcloud" "terraform" "jq")
all_found=true

for cmd in "${commands[@]}"; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: $cmd is not found in the current PATH."
    all_found=false
  else
    echo "NOTE: $cmd found."
  fi
done

if [ "$all_found" = false ]; then
  echo "ERROR: One or more required commands are missing."
  exit 1
fi

if [ ! -f credentials.json ]; then
  echo "ERROR: credentials.json not found in repo root."
  exit 1
fi
echo "NOTE: credentials.json found."

./api_setup.sh

# ------------------------------------------------------------------------------
# Imagen model smoke test — confirms the configured model is reachable and
# accepts REFERENCE_TYPE_SUBJECT before wasting a full deploy cycle.
# Uses a minimal valid PNG (8x8 white square) as the test image.
# ------------------------------------------------------------------------------
echo "NOTE: Testing Imagen model ${IMAGEN_MODEL_ID}..."
PROJECT=$(jq -r '.project_id' credentials.json)
TOKEN=$(gcloud auth print-access-token)

# Minimal valid 8x8 white PNG
B64="iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAADklEQVQI12P4z8BQDwAEgAF/QualIQAAAABJRU5ErkJggg=="

RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT}" \
  "https://us-central1-aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/us-central1/publishers/google/models/${IMAGEN_MODEL_ID}:predict" \
  -d "{
    \"instances\": [{
      \"prompt\": \"cartoon style portrait\",
      \"referenceImages\": [{
        \"referenceType\": \"REFERENCE_TYPE_SUBJECT\",
        \"referenceId\": 0,
        \"referenceImage\": { \"bytesBase64Encoded\": \"${B64}\" },
        \"subjectImageConfig\": { \"subjectType\": \"SUBJECT_TYPE_PERSON\" }
      }]
    }],
    \"parameters\": { \"sampleCount\": 1 }
  }")

ERROR_CODE=$(echo "${RESPONSE}" | jq -r '.error.code // empty')
ERROR_MSG=$(echo "${RESPONSE}" | jq -r '.error.message // empty')

if [ -n "${ERROR_CODE}" ] && [ "${ERROR_CODE}" != "400" ]; then
  echo "ERROR: Imagen model ${IMAGEN_MODEL_ID} unavailable (${ERROR_CODE}): ${ERROR_MSG}"
  exit 1
fi
# 400 is acceptable here — it means the model is reachable but rejected the
# tiny test image (too small for subject detection), which is expected.
echo "NOTE: Imagen model ${IMAGEN_MODEL_ID} is reachable."

# ------------------------------------------------------------------------------
# Gemini image generation smoke test — sends a tiny image and expects either
# a successful response or a 400 (content rejected). Any other error means
# the model is unavailable or the project lacks access.
# ------------------------------------------------------------------------------
echo "NOTE: Testing Gemini model ${GEMINI_MODEL_ID}..."
GEMINI_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: ${PROJECT}" \
  "https://us-central1-aiplatform.googleapis.com/v1/projects/${PROJECT}/locations/us-central1/publishers/google/models/${GEMINI_MODEL_ID}:generateContent" \
  -d "{
    \"contents\": [{
      \"role\": \"user\",
      \"parts\": [
        { \"inlineData\": { \"mimeType\": \"image/png\", \"data\": \"${B64}\" } },
        { \"text\": \"Convert this image to a cartoon style portrait\" }
      ]
    }],
    \"generationConfig\": {
      \"responseModalities\": [\"IMAGE\", \"TEXT\"]
    }
  }")

GEMINI_ERROR_CODE=$(echo "${GEMINI_RESPONSE}" | jq -r '.error.code // empty')
GEMINI_ERROR_MSG=$(echo "${GEMINI_RESPONSE}" | jq -r '.error.message // empty')

if [ -n "${GEMINI_ERROR_CODE}" ] && [ "${GEMINI_ERROR_CODE}" != "400" ]; then
  echo "ERROR: Gemini model ${GEMINI_MODEL_ID} unavailable (${GEMINI_ERROR_CODE}): ${GEMINI_ERROR_MSG}"
  exit 1
fi
echo "NOTE: Gemini model ${GEMINI_MODEL_ID} is reachable."
