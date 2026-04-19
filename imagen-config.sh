#!/usr/bin/env bash
# ==============================================================================
# imagen-config.sh — Vertex AI Imagen model selection
# ==============================================================================
# Sourced by apply.sh and destroy.sh. Change IMAGEN_MODEL_ID here to switch
# models without touching any Terraform or Python code.
#
# Imagen 3 editing models:
#   imagen-3.0-capability-001   — full quality, supports edit_image
# ==============================================================================

export IMAGEN_MODEL_ID="imagen-3.0-capability-002"
