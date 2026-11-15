#!/usr/bin/env bash
# Stop or deallocate the current stage's compute. State and configuration are kept.
#
# Usage: scripts/ops/sleep.sh [--targets all|vm,aks,appgw] [--no-wait]
#   --targets  which kinds of compute to stop (default: all that exist)
#   --no-wait  return as soon as the stop requests are sent
set -euo pipefail
# shellcheck source=scripts/ops/lib.sh
source "$(dirname "$0")/lib.sh"

usage() {
  sed -n '3,6s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

targets=all
wait=1
while (($#)); do
  case $1 in
    --targets) targets=${2:-}; shift 2 ;;
    --no-wait) wait=0; shift ;;
    *) usage ;;
  esac
done
check_targets "$targets" || exit 2

rows=$(nebo_compute "$targets" | jq -c 'select(.power != "stopped")')
awake=()
to_array awake "$rows"
if ((${#awake[@]} == 0)); then
  log "Nothing to put to sleep: no '$targets' compute is running."
  summary "Nothing to put to sleep: no \`$targets\` compute is running."
  exit 0
fi

for r in "${awake[@]}"; do
  stop_resource "$r"
  set_tags "$(jq -r .id <<<"$r")" "$TAG_SLEEP_AFTER=asleep" "$TAG_FIRST_SEEN="
  log "$(jq -r .name <<<"$r"): stopping"
done

if ((wait)); then
  log "Waiting until everything is stopped (up to 15 minutes)..."
  printf '%s\n' "${awake[@]}" | wait_for stopped 900
fi
summary "### Put ${#awake[@]} resource(s) to sleep"
"$(dirname "$0")/status.sh"
