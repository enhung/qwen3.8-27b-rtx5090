#!/usr/bin/env bash
set -euo pipefail

# Frozen GPUtw Light profile reported in the 2026-09-12 handoff.
# Run inside the P1 image only after confirming the pinned /vault snapshot.
export MODEL_DIR=/vault/qwen38/models/qwen3.8-27b-nvfp4
export MAX_JOBS=2
export NVCC_THREADS=2

exec /app/entrypoint-auth.sh \
  --served-model-name qwen3.8-27b \
  --host 0.0.0.0 \
  --port 8000 \
  --max-model-len 131072 \
  --gpu-memory-utilization 0.95 \
  --max-num-seqs 4 \
  --kv-cache-dtype fp8 \
  --enable-prefix-caching \
  --reasoning-parser qwen3 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_xml \
  --trust-remote-code
