#!/usr/bin/env bash
set -euo pipefail

GATEWAY_URL=$(jq -r '.apiBaseUrl' 02-webapp/config.json)
WEBAPP_URL=$(cd 02-webapp && terraform output -raw webapp_url 2>/dev/null || echo "N/A")

echo ""
echo "================================================================================="
echo "  Deployment complete!"
echo "================================================================================="
echo "  API     : ${GATEWAY_URL}/notes"
echo "  Web app : ${WEBAPP_URL}"
echo "================================================================================="
