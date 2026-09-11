#!/usr/bin/env bash
set -euo pipefail

MODEL_REPO="${MODEL_REPO:-gittensor-model-hub/Qwen3.8-27B-NVFP4-RTX5090}"
MODEL_REVISION="${MODEL_REVISION:-0cc27958cefbbe231782ec8511de8c4eb5233348}"
MODEL_DIR="${MODEL_DIR:-/workspace/models/qwen3.8-27b-nvfp4}"

mkdir -p "${MODEL_DIR}"

if [ ! -f "${MODEL_DIR}/config.json" ]; then
  echo "Downloading ${MODEL_REPO} @ ${MODEL_REVISION} to ${MODEL_DIR} ..."
  HF_XET_HIGH_PERFORMANCE=1 hf download \
    "${MODEL_REPO}" \
    --revision "${MODEL_REVISION}" \
    --local-dir "${MODEL_DIR}"
else
  echo "Using existing local model at ${MODEL_DIR}"
fi

echo "Starting vLLM from local model directory: ${MODEL_DIR}"
exec vllm serve "${MODEL_DIR}" "$@"
