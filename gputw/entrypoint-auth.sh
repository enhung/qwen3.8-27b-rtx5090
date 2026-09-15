#!/usr/bin/env bash
set -euo pipefail

# GPUtw mounts /vault across instances; the image contains no key material.
export MODEL_DIR="${MODEL_DIR:-/vault/qwen38/models/qwen3.8-27b-nvfp4}"
export MAX_JOBS="${MAX_JOBS:-2}"
export NVCC_THREADS="${NVCC_THREADS:-2}"

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

# GPUtw's SSH gateway expects sshd to be present before it wires the route.
# Starting it here avoids the platform bootstrap apt path, which can fail on
# the Vault-backed apt lists mount with an Invalid cross-device link error.
if command -v sshd >/dev/null 2>&1; then
  mkdir -p /run/sshd
  # Generate unique host keys at runtime after build-time keys were removed.
  if ! compgen -G "/etc/ssh/ssh_host_*_key" >/dev/null; then
    ssh-keygen -A
  fi
  /usr/sbin/sshd
fi

# A fresh GPUtw custom image with no supplied args uses the profile supervisor.
# Existing v2-style args pass through unchanged for one-shot compatibility.
if [[ $# -eq 0 ]]; then
  exec /app/profile-supervisor.sh
fi

# vLLM's built-in key only protects selected prefixes. The middleware also
# blocks unauthenticated and non-allowlisted routes on the public listener.
exec /app/entrypoint-gputw.sh "$@" \
  --middleware gputw_auth_middleware.AuthMiddleware \
  --disable-fastapi-docs
