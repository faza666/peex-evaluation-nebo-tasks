#!/usr/bin/env bash
# List every NEBo resource by stack, with the power state of compute and when it is due to sleep.
#
# Usage: scripts/ops/status.sh [--json]
set -euo pipefail
# shellcheck source=scripts/ops/lib.sh
source "$(dirname "$0")/lib.sh"

case ${1:-} in
  "") json=0 ;;
  --json) json=1 ;;
  *) echo "Usage: $0 [--json]" >&2; exit 2 ;;
esac

rows=$(nebo_resources)
if ((json)); then
  jq -s . <<<"$rows"
  exit 0
fi
if [[ -z $rows ]]; then
  echo "No NEBo resources exist."
  summary "No NEBo resources exist."
  exit 0
fi

dash() { jq -r '[.stack, .type, .name, (.power | if . == "" then "-" else . end),
                 (.sleepAfter | if . == "" then "-" else . end)] | @tsv'; }
{
  printf 'STACK\tTYPE\tNAME\tPOWER\tSLEEP-AFTER\n'
  dash <<<"$rows"
} | column -t -s $'\t'

total=$(jq -s length <<<"$rows")
awake=$(jq -s '[.[] | select(.power == "running" or .power == "transitioning")] | length' <<<"$rows")
echo
echo "$total resources; $awake compute resource(s) awake."

summary "### NEBo status: $total resources, $awake compute awake"
summary ""
summary "| Stack | Type | Name | Power | Sleep after |"
summary "|---|---|---|---|---|"
while IFS=$'\t' read -r stack type name power sleep_after; do
  summary "| $stack | $type | $name | $power | $sleep_after |"
done < <(dash <<<"$rows")
