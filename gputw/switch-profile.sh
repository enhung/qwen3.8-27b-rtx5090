#!/usr/bin/env bash
set -euo pipefail

# Change the profile persisted on /vault and ask the PID-1 supervisor to
# restart only the vLLM child. This avoids destroying the GPUtw instance.

PROFILE_FILE="${QWEN_PROFILE_FILE:-/vault/qwen38/config/profile}"
profile="${1:-}"
case "$profile" in
  bootstrap|light|light16|mtp16) ;;
  *) echo "usage: $0 {bootstrap|light|light16|mtp16}" >&2; exit 2 ;;
esac

if ! tr '\0' ' ' < /proc/1/cmdline | grep -q 'profile-supervisor.sh'; then
  echo "PID 1 is not the profile supervisor; refusing to signal it" >&2
  exit 1
fi

mkdir -p "$(dirname "$PROFILE_FILE")"
tmp="${PROFILE_FILE}.tmp.$$"
umask 077
printf '%s\n' "$profile" > "$tmp"
mv -f "$tmp" "$PROFILE_FILE"
kill -HUP 1
echo "profile switch requested: $profile"
