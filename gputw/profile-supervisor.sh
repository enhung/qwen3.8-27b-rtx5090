#!/usr/bin/env bash
set -euo pipefail

# Keep a stable PID 1 while allowing a running GPUtw instance to switch the
# vLLM serve profile without recreating the instance. The profile file lives
# on /vault so it survives a container restart; a HUP drains the child and
# starts the selected profile with the same authenticated middleware.

PROFILE_FILE="${QWEN_PROFILE_FILE:-/vault/qwen38/config/profile}"
MODEL_DIR="${MODEL_DIR:-/vault/qwen38/models/qwen3.8-27b-nvfp4}"
MAX_JOBS="${MAX_JOBS:-2}"
NVCC_THREADS="${NVCC_THREADS:-2}"
export MODEL_DIR MAX_JOBS NVCC_THREADS

child_pid=""
shutdown_requested=0
restart_requested=0

profile_args() {
  local profile="$1"
  case "$profile" in
    light)
      printf '%s\0' \
        --served-model-name qwen3.8-27b \
        --host 0.0.0.0 --port 8000 \
        --max-model-len 131072 \
        --gpu-memory-utilization 0.95 \
        --max-num-seqs 4 \
        --kv-cache-dtype fp8 \
        --enable-prefix-caching \
        --reasoning-parser qwen3 \
        --enable-auto-tool-choice \
        --tool-call-parser qwen3_xml \
        --trust-remote-code
      ;;
    light16)
      printf '%s\0' \
        --served-model-name qwen3.8-27b \
        --host 0.0.0.0 --port 8000 \
        --max-model-len 131072 \
        --gpu-memory-utilization 0.95 \
        --max-num-seqs 16 \
        --kv-cache-dtype fp8 \
        --enable-prefix-caching \
        --reasoning-parser qwen3 \
        --enable-auto-tool-choice \
        --tool-call-parser qwen3_xml \
        --trust-remote-code
      ;;
    mtp16)
      printf '%s\0' \
        --served-model-name qwen3.8-27b \
        --host 0.0.0.0 --port 8000 \
        --max-model-len 131072 \
        --gpu-memory-utilization 0.965 \
        --max-num-seqs 16 \
        --kv-cache-dtype fp8 \
        --enable-prefix-caching \
        --reasoning-parser qwen3 \
        --enable-auto-tool-choice \
        --tool-call-parser qwen3_xml \
        --trust-remote-code \
        --speculative-config '{"method":"mtp","num_speculative_tokens":2}'
      ;;
    *)
      echo "unknown Qwen profile '$profile' (use light, light16, or mtp16); falling back to light" >&2
      profile_args light
      ;;
  esac
}

read_profile() {
  local profile="light"
  if [[ -r "$PROFILE_FILE" ]]; then
    IFS= read -r profile < "$PROFILE_FILE" || true
  fi
  case "$profile" in
    light|light16|mtp16) printf '%s' "$profile" ;;
    *) printf 'light' ;;
  esac
}

stop_child() {
  if [[ -n "$child_pid" ]] && kill -0 "$child_pid" 2>/dev/null; then
    kill -TERM "$child_pid" 2>/dev/null || true
  fi
}

on_hup() {
  restart_requested=1
  stop_child
}

on_shutdown() {
  shutdown_requested=1
  stop_child
}

trap on_hup HUP
trap on_shutdown TERM INT

while (( !shutdown_requested )); do
  profile="$(read_profile)"
  mapfile -d '' -t args < <(profile_args "$profile")
  echo "Starting Qwen profile=$profile (profile_file=$PROFILE_FILE)"
  /app/entrypoint-gputw.sh "${args[@]}" \
    --middleware gputw_auth_middleware.AuthMiddleware \
    --disable-fastapi-docs &
  child_pid=$!
  set +e
  wait "$child_pid"
  child_rc=$?
  set -e
  child_pid=""

  (( shutdown_requested )) && exit 0
  if (( restart_requested )); then
    restart_requested=0
    continue
  fi

  echo "vLLM exited with status $child_rc; restarting profile=$profile" >&2
  sleep 2
done

exit 0
