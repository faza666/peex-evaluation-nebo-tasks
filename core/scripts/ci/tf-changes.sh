#!/usr/bin/env bash
# Turn a Terraform plan into a list of changes by resource address, for the job summary and the pull request.
#
# Reads the plan as JSON (terraform show -json). Writes tf-changes.md in the current directory and prints it.
# Only addresses and actions are listed: no attribute values, so no IDs, addresses or webhook URLs reach the
# summary or a comment of this public repository. The full plan stays in the masked run log.
# GitHub Actions outputs: count (resources that change).
#
# Usage: core/scripts/ci/tf-changes.sh plan.json <stack>
set -euo pipefail

plan=${1:?usage: tf-changes.sh plan.json <stack>}
stack=${2:?usage: tf-changes.sh plan.json <stack>}

changes=$(jq -c '[.resource_changes[]?
  | select(.mode == "managed")
  | (.change.actions) as $a
  | (if $a == ["create"] then "add"
     elif $a == ["update"] then "change"
     elif $a == ["delete"] then "destroy"
     elif ($a | sort) == ["create", "delete"] then "replace"
     else empty end) as $action
  | {action: $action, address}]
  | sort_by(.action, .address)' "$plan")

count=$(jq length <<<"$changes")
n() { jq --arg a "$1" '[.[] | select(.action == $a)] | length' <<<"$changes"; }

{
  if ((count == 0)); then
    echo "No changes: stack \`$stack\` matches its code."
  else
    echo "**$count change(s)** in stack \`$stack\`: $(n add) to add, $(n change) to change," \
      "$(n replace) to replace, $(n destroy) to destroy."
    echo
    echo "| | Resource |"
    echo "|---|---|"
    jq -r '.[]
      | ({add: "➕ add", change: "✏️ change", replace: "♻️ replace", destroy: "➖ destroy"}[.action]) as $icon
      | "| \($icon) | `\(.address)` |"' <<<"$changes"
  fi
} >tf-changes.md
cat tf-changes.md

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  echo "count=$count" >>"$GITHUB_OUTPUT"
fi
