#!/usr/bin/env bash
# Stop or deallocate the stage's compute; state and configuration are kept.
#
# Usage: core/scripts/ops/sleep.sh [--targets all|vm,aks,appgw] [--no-wait]
#   --targets  which compute kinds to put to sleep (default: all)
#   --no-wait  return as soon as the stop requests are sent
set -euo pipefail
# shellcheck source=core/scripts/ops/lib.sh
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
  log "No '$targets' compute is running."
  summary "No \`$targets\` compute is running."
else
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
fi

"$(dirname "$0")/status.sh"
