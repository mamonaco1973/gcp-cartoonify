#!/usr/bin/env bash
set -euo pipefail

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
