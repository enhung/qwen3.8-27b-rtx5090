#!/usr/bin/env bash
set -euo pipefail

# GPUtw mounts /vault across instances; the image contains no key material.
export MODEL_DIR="${MODEL_DIR:-/vault/qwen38/models/qwen3.8-27b-nvfp4}"
export MAX_JOBS="${MAX_JOBS:-2}"
export NVCC_THREADS="${NVCC_THREADS:-2}"

# A fresh GPUtw custom image with no supplied args still uses the frozen
# Light invocation. Existing v2-style args pass through unchanged.
if [[ $# -eq 0 ]]; then
  exec /app/SAFE_BASELINE.sh
fi

API_KEY_FILE="${API_KEY_FILE:-/vault/qwen38/config/api_key}"
if [[ ! -f "$API_KEY_FILE" || ! -r "$API_KEY_FILE" ]]; then
  echo "API key file is missing or unreadable" >&2
  exit 1
fi

VLLM_API_KEY=""
IFS= read -r VLLM_API_KEY < "$API_KEY_FILE" || [[ -n "$VLLM_API_KEY" ]]
if [[ -z "$VLLM_API_KEY" || "$VLLM_API_KEY" =~ [[:space:]] ]] || \
   ! awk 'NR > 1 { exit 1 }' "$API_KEY_FILE"; then
  echo "API key file must contain one non-empty token" >&2
  exit 1
fi
export VLLM_API_KEY
unset API_KEY_FILE

# vLLM's built-in key only protects selected prefixes. The middleware also
# blocks unauthenticated and non-allowlisted routes on the public listener.
exec /app/entrypoint-gputw.sh "$@" \
  --middleware gputw_auth_middleware.AuthMiddleware \
  --disable-fastapi-docs
