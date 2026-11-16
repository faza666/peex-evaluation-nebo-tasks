#!/usr/bin/env bash
# Create the registry if missing, start the stage's compute, tag it to sleep after N hours, wait until it runs.
#
# Usage: scripts/ops/wake-up.sh [--targets all|vm,aks,appgw] [--hours 1-12]
#   --targets  which kinds of compute to start (default: all that exist)
#   --hours    when sleep-guard may put it back to sleep (default 4, maximum 12)
set -euo pipefail
# shellcheck source=scripts/ops/lib.sh
source "$(dirname "$0")/lib.sh"

usage() {
  sed -n '3,6s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

targets=all
hours=4
while (($#)); do
  case $1 in
    --targets) targets=${2:-}; shift 2 ;;
    --hours) hours=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done
check_targets "$targets" || exit 2
if ! [[ $hours =~ ^[0-9]+$ ]] || ((hours < 1 || hours > 12)); then
  log "ERROR: --hours must be a whole number from 1 to 12 (got '$hours')"
  exit 2
fi

# The registry first: CI pushes to it even in stages with no compute to start.
ensure_registry

rows=$(nebo_compute "$targets")
compute=()
to_array compute "$rows"
if ((${#compute[@]} == 0)); then
  log "Nothing to wake: no '$targets' compute exists in the current stage."
  summary "Nothing to wake: no \`$targets\` compute exists in the current stage."
  exit 0
fi

until=$(iso_in_hours "$hours")
for r in "${compute[@]}"; do
  name=$(jq -r .name <<<"$r")
  set_tags "$(jq -r .id <<<"$r")" "$TAG_SLEEP_AFTER=$until" "$TAG_FIRST_SEEN="
  if [[ $(jq -r .power <<<"$r") == running ]]; then
    log "$name: already running; sleep-after moved to $until"
  else
    start_resource "$r"
    log "$name: starting"
  fi
done

log "Waiting until everything is running (up to 15 minutes)..."
printf '%s\n' "${compute[@]}" | wait_for running 900
log "Awake. sleep-guard will put it back to sleep after $until."
summary "### Awake until $until"
summary ""
summary "Run **sleep** when you take a break; otherwise sleep-guard does it within an hour after $until."
"$(dirname "$0")/status.sh"
