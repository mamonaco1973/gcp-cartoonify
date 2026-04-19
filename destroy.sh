#!/usr/bin/env bash
set -euo pipefail

# ─── Destroy web application first (removes GCS objects) ─────────────────────

echo "NOTE: Destroying web application..."
cd 02-webapp
terraform destroy -auto-approve
cd ..

# ─── Destroy backend infrastructure ──────────────────────────────────────────

echo "NOTE: Destroying backend infrastructure..."
cd 01-functions
terraform destroy -auto-approve
cd ..

echo "NOTE: Destroy complete."
