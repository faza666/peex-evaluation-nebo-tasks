#!/usr/bin/env bash
# The safety net, run hourly by sleep-guard.yml. For every NEBo compute resource that is awake:
#   - past its nebo:sleep-after time            -> put it to sleep;
#   - running without a valid sleep-after time  -> warn and tag nebo:first-seen-awake, and put it
#     to sleep once it has run untagged for more than 2 hours (e.g. started from the portal).
# It only reports when it acts, so it is quiet most of the time.
#
# Usage: core/scripts/ops/sleep-guard.sh [--dry-run]
set -euo pipefail
# shellcheck source=core/scripts/ops/lib.sh
source "$(dirname "$0")/lib.sh"

GRACE_SECONDS=$((2 * 3600))
dry_run=0
case ${1:-} in
  "") ;;
  --dry-run) dry_run=1 ;;
  *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac
act() { if ((dry_run)); then log "(dry run) would: $*"; else "$@"; fi; }

# Stopped or deallocated, and tagged asleep.
put_to_sleep() { # json line
  act stop_resource "$1"
  act set_tags "$(jq -r .id <<<"$1")" "$TAG_SLEEP_AFTER=asleep" "$TAG_FIRST_SEEN="
}

now=$(now_epoch)
rows=$(nebo_resources | jq -c 'select(.computeKind != "other" and (.power == "running" or .power == "transitioning"))')
awake=()
to_array awake "$rows"
log "${#awake[@]} compute resource(s) awake"

actions=()
for r in "${awake[@]}"; do
  id=$(jq -r .id <<<"$r")
  name=$(jq -r .name <<<"$r")
  sleep_after=$(jq -r .sleepAfter <<<"$r")
  first_seen=$(jq -r .firstSeen <<<"$r")
  due=$(to_epoch "$sleep_after")

  if [[ -n $due ]]; then
    if ((now > due)); then
      warn "$name was due to sleep at $sleep_after; put to sleep now"
      put_to_sleep "$r"
      actions+=("| $name | past sleep-after ($sleep_after) | put to sleep |")
    else
      log "$name: awake until $sleep_after"
    fi
    continue
  fi

  seen=$(to_epoch "$first_seen")
  if [[ -z $seen ]]; then
    deadline=$(date -u -d "+2 hours" +%Y-%m-%dT%H:%MZ)
    warn "$name is running without a sleep-after time (started outside wake-up?); it will be put to sleep after $deadline unless wake-up is used"
    act set_tags "$id" "$TAG_FIRST_SEEN=$(date -u +%Y-%m-%dT%H:%MZ)"
    actions+=("| $name | running without sleep-after | warned; sleeps after $deadline |")
  elif ((now - seen > GRACE_SECONDS)); then
    warn "$name has run without a sleep-after time since $first_seen; put to sleep now"
    put_to_sleep "$r"
    actions+=("| $name | untagged for over 2 h (since $first_seen) | put to sleep |")
  else
    log "$name: untagged, in its 2 h grace period since $first_seen"
  fi
done

if ((${#actions[@]} == 0)); then
  log "Nothing to do."
  exit 0
fi
summary "### sleep-guard acted$( ((dry_run)) && echo ' (dry run)')"
summary ""
summary "| Resource | Reason | Action |"
summary "|---|---|---|"
for a in "${actions[@]}"; do summary "$a"; done
