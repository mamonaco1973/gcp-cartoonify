#!/usr/bin/env bash
set -euo pipefail

GATEWAY_URL=$(jq -r '.apiBaseUrl' 03-webapp/config.json 2>/dev/null || echo "")
WEBAPP_URL=$(cd 03-webapp && terraform output -raw webapp_url 2>/dev/null || echo "N/A")

echo ""
echo "================================================================================"
echo "  gcp-cartoonify — deployment complete"
echo "================================================================================"
echo "  API Gateway : ${GATEWAY_URL}"
echo "  Web App     : ${WEBAPP_URL}"
echo "================================================================================"
echo ""
# echo "  Routes:"
# echo "    POST   ${GATEWAY_URL}/upload-url"
# echo "    POST   ${GATEWAY_URL}/generate"
# echo "    GET    ${GATEWAY_URL}/result/{job_id}"
# echo "    GET    ${GATEWAY_URL}/history"
# echo "    DELETE ${GATEWAY_URL}/history/{job_id}"
# echo "================================================================================"
