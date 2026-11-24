#!/usr/bin/env bash
# Turn a core/rbac plan into the list the subscription owner reviews, and refuse what must never be requested.
#
# Reads the plan as JSON (terraform show -json). Writes, in the current directory:
#   rbac-changes.json  [{action, principal, role, scope}], names only: no IDs, so it can go into public logs
#   rbac-changes.md    the same list as a Markdown table, for the job summary and the pull request
# and prints the table. Fails when a change names Owner, User Access Administrator or Role Based Access Control
# Administrator, or a scope outside the five NEBo resource groups. core/rbac refuses both too; this is the
# second check, on what Terraform would actually do.
# GitHub Actions outputs: count, adds, removes, digest (sha256 of rbac-changes.json), changes (its content).
#
# Usage: core/scripts/ci/rbac-changes.sh plan.json
set -euo pipefail

plan=${1:?usage: rbac-changes.sh plan.json}

# One entry per change. A replacement is a removal plus an addition. The resource key in core/rbac is
# "<principal> | <role> | <scope key>"; the role and scope that are checked come from the plan itself.
jq -S '
  def plain:
    if startswith("rg:") then "rg-nebo-" + ltrimstr("rg:")
    elif startswith("container:") then "state container " + ltrimstr("container:")
    elif startswith("mi:") then "identity " + ltrimstr("mi:")
    else (split("/") | "\(.[1]) in rg-nebo-\(.[0])")
    end;
  [ .resource_changes[]?
    | select(.mode == "managed" and .type == "azurerm_role_assignment")
    | .change as $c
    | ($c.actions | if . == ["create"] then ["add"]
                    elif . == ["delete"] then ["remove"]
                    elif (. == ["delete", "create"] or . == ["create", "delete"]) then ["remove", "add"]
                    elif . == ["update"] then ["change"]
                    else [] end)[] as $action
    | (.index | split(" | ")) as $key
    | {
        action: $action,
        principal: $key[0],
        role: (if $action == "remove" then $c.before else $c.after end).role_definition_name,
        scope: ($key[2] | plain),
        azure_scope: ((if $action == "remove" then $c.before else $c.after end).scope // "")
      }
  ] | sort_by(.action, .principal, .role, .scope)' "$plan" >rbac-checked.json

# The checks need the real scopes; the published list keeps only names.
forbidden=$(jq -r '.[] | select(.role // "" | ascii_downcase
  | IN("owner", "user access administrator", "role based access control administrator"))
  | "\(.action) \(.role) -> \(.principal)"' rbac-checked.json)
outside=$(jq -r '.[] | select(.azure_scope
  | test("^/subscriptions/[^/]+/resourceGroups/rg-nebo-(mgmt|core|stage-a|stage-b|stage-c)(/|$)"; "i") | not)
  | "\(.action) \(.role) -> \(.principal) @ \(.scope)"' rbac-checked.json)
jq -c 'map(del(.azure_scope))' rbac-checked.json >rbac-changes.json
rm rbac-checked.json

count=$(jq length rbac-changes.json)
adds=$(jq '[.[] | select(.action == "add")] | length' rbac-changes.json)
removes=$(jq '[.[] | select(.action == "remove")] | length' rbac-changes.json)
digest=$(sha256sum rbac-changes.json | cut -c1-64)

{
  if ((count == 0)); then
    echo "No changes: the role assignments in Azure match \`core/rbac/grants.yaml\`."
  else
    echo "**$count change(s)** to NEBo role assignments: $adds to add, $removes to remove."
    echo
    echo "| | Identity | Role | Scope |"
    echo "|---|---|---|---|"
    jq -r '.[]
      | (if .action == "add" then "➕ add" elif .action == "remove" then "➖ remove" else "✏️ change" end) as $icon
      | "| \($icon) | \(.principal) | \(.role) | \(.scope) |"' rbac-changes.json
    echo
    echo "Digest \`${digest::12}\`: the apply job re-plans and stops if its list has a different digest."
  fi
} >rbac-changes.md
cat rbac-changes.md

if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    printf 'count=%s\nadds=%s\nremoves=%s\ndigest=%s\n' "$count" "$adds" "$removes" "$digest"
    printf 'changes=%s\n' "$(cat rbac-changes.json)"
  } >>"$GITHUB_OUTPUT"
fi

status=0
if [[ -n $forbidden ]]; then
  while read -r line; do
    echo "::error title=Refused role::$line. Owner, User Access Administrator and Role Based Access Control" \
      "Administrator are never requested through rbac.yml."
  done <<<"$forbidden"
  status=1
fi
if [[ -n $outside ]]; then
  while read -r line; do
    echo "::error title=Refused scope::$line: in the plan, its scope is outside the five NEBo resource groups."
  done <<<"$outside"
  status=1
fi
exit "$status"
