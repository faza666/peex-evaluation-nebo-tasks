#!/usr/bin/env bash
# Deploy one image to one Container App in rg-nebo-stage-a, as a new revision that gets traffic only after it
# answers. cd.yml runs it for menu-dev and then for menu-prod, signed in as mi-nebo-cd-a.
#
#   1. Pin all traffic on the revision that serves now, so the new revision starts with none.
#   2. Start a new revision with <registry>/menu:<tag>, from the registry the app already pulls from.
#   3. Smoke test the new revision on its own address: /health, /ready and /menu answer 200.
#   4. Move all traffic to it, then smoke test the app's address: it must serve the new revision's version.
# If 2, 3 or 4 fails, all traffic goes back to the previous revision and the new one is deactivated.
# An app that doesn't exist yet is skipped: the aca stack creates it with the image of the commit it applies.
#
# Usage: core/scripts/ci/aca-deploy.sh <app> <tag>
#   tag  an image tag docker-build.yml pushes: v<MAJOR.MINOR.PATCH> or sha-<7 hex characters>
# In Actions, writes the outputs result (deployed | rolled-back | skipped), url, revision, previous and version
# (what /health reports, e.g. v3.0.14), and a table to the job summary.
set -euo pipefail

app=${1:?usage: aca-deploy.sh <app> <tag>}
tag=${2:?usage: aca-deploy.sh <app> <tag>}
rg="rg-nebo-stage-a"
api=2024-03-01 # Microsoft.App API version for the traffic PATCH

if [[ ! $tag =~ ^(v[0-9]+\.[0-9]+\.[0-9]+|sha-[0-9a-f]{7})$ ]]; then
  echo "::error title=Not an image tag::'$tag' is not a tag docker-build.yml pushes (v<version> or sha-<7>)."
  exit 2
fi

out() { if [[ -n ${GITHUB_OUTPUT:-} ]]; then printf '%s=%s\n' "$1" "$2" >>"$GITHUB_OUTPUT"; fi; }
# summary <revision> <version> <result>
summary() {
  if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    # shellcheck disable=SC2016  # the backticks are Markdown
    printf '### %s\n\n| Revision | Image tag | Version | Result |\n|---|---|---|---|\n| %s | `%s` | %s | %s |\n' \
      "$app" "$1" "$tag" "$2" "$3" >>"$GITHUB_STEP_SUMMARY"
  fi
}

err=$(mktemp)
trap 'rm -f "$err"' EXIT
if ! json=$(az containerapp show --name "$app" --resource-group "$rg" --output json --only-show-errors 2>"$err"); then
  if grep -q ResourceNotFound "$err"; then
    echo "::notice title=$app doesn't exist yet::The aca stack creates it, with the image of the commit it applies." \
      "Nothing was deployed."
    out result skipped
    summary – – "skipped: the app doesn't exist yet"
    exit 0
  fi
  cat "$err" >&2
  exit 1
fi

id=$(jq -r .id <<<"$json")
url="https://$(jq -r .properties.configuration.ingress.fqdn <<<"$json")"
registry=$(jq -r '.properties.configuration.registries[0].server // empty' <<<"$json")
image="$registry/menu:$tag"
# Unique per run and attempt, so a re-run or a redeploy of the same tag gets its own revision.
suffix="${tag//./-}-r${GITHUB_RUN_NUMBER:-0}-${GITHUB_RUN_ATTEMPT:-$(date +%s)}"
new="$app--$suffix"
# The revision with the most traffic; "latest" (the first revision, from Terraform) means the latest ready one.
previous=$(jq -r '
  [.properties.configuration.ingress.traffic[]? | select(.weight > 0)] | max_by(.weight) // {}
  | if .latestRevision then $ready else (.revisionName // "") end' \
  --arg ready "$(jq -r '.properties.latestReadyRevisionName // ""' <<<"$json")" <<<"$json")
out url "$url"
out revision "$new"
out previous "$previous"
echo "App $app: $url, serving ${previous:-nothing}. New revision $new with $image."

# set_traffic <revision>: all traffic on that revision and none on any other. PATCH is a JSON merge patch, so only
# the traffic list changes; the CLI's own command would keep every revision ever listed.
set_traffic() {
  local body i state
  body=$(jq -nc --arg r "$1" '{properties: {configuration: {ingress: {traffic: [{revisionName: $r, weight: 100}]}}}}')
  az rest --method patch --url "https://management.azure.com$id?api-version=$api" --body "$body" \
    --only-show-errors --output none || return 1
  for ((i = 0; i < 60; i++)); do # the PATCH is accepted at once and applied in the background
    state=$(az containerapp show --name "$app" --resource-group "$rg" --output json --only-show-errors | jq -r --arg r "$1" '
      [.properties.provisioningState,
       ([.properties.configuration.ingress.traffic[] | select(.weight == 100) | .revisionName] == [$r])] | @tsv')
    case $state in
      $'Succeeded\ttrue') return 0 ;;
      Failed*) return 1 ;;
    esac
    sleep 5
  done
  return 1
}

# wait_revision: until the new revision is provisioned, for up to 10 minutes.
wait_revision() {
  local i state
  for ((i = 0; i < 120; i++)); do
    state=$(az containerapp revision show --name "$app" --resource-group "$rg" --revision "$new" --only-show-errors \
      --query "[properties.provisioningState, properties.runningState]" --output tsv 2>/dev/null || true)
    case $state in
      Provisioned*) return 0 ;;
      Failed* | *Failed) return 1 ;;
    esac
    sleep 5
  done
  return 1
}

# smoke <base URL>: /health, /ready and /menu answer 200, with retries while a cold start finishes. Sets $served
# to the version /health reports.
smoke() {
  local path
  for path in /health /ready /menu; do
    if ! curl --fail --silent --show-error --output /dev/null --max-time 15 \
      --retry 10 --retry-delay 6 --retry-all-errors "$1$path"; then
      echo "::error title=Smoke test failed::$1$path did not answer 200."
      return 1
    fi
    echo "$1$path: 200"
  done
  served=$(curl --fail --silent --max-time 15 "$1/health" | jq -r '.version // ""')
}

# rollback <reason>
rollback() {
  echo "::error title=$app not deployed::$1 All traffic goes back to ${previous:-the revision that had it}."
  if [[ -n $previous ]] && ! set_traffic "$previous"; then
    echo "::error title=Rollback failed::Traffic could not be moved back to $previous. Check $app in the portal."
  fi
  az containerapp revision deactivate --name "$app" --resource-group "$rg" --revision "$new" --only-show-errors \
    --output none 2>/dev/null || true
  out result rolled-back
  summary "\`$new\`" – "rolled back to \`${previous:-–}\`: $1"
  exit 1
}

# 1. The new revision must start without traffic.
if [[ -n $previous ]]; then
  set_traffic "$previous" || { echo "::error title=Traffic not pinned::Could not pin traffic on $previous."; exit 1; }
fi

# 2. New revision.
if ! az containerapp update --name "$app" --resource-group "$rg" --image "$image" --revision-suffix "$suffix" \
  --no-wait --only-show-errors --output none; then
  rollback "The new revision could not be created."
fi
wait_revision || rollback "Revision $new did not start: is $image in the registry?"

# 3. Smoke test on the revision's own address.
revision_url="https://$(az containerapp revision show --name "$app" --resource-group "$rg" --revision "$new" \
  --query properties.fqdn --output tsv --only-show-errors)"
smoke "$revision_url" || rollback "Revision $new failed its smoke test."
version=$served
out version "$version"

# 4. All traffic to the new revision, then the app's own address must serve it.
set_traffic "$new" || rollback "Traffic could not be moved to $new."
smoke "$url" || rollback "$url failed its smoke test after the traffic moved."
if [[ $served != "$version" ]]; then
  rollback "$url serves version '$served', not the new revision's '$version'."
fi

echo "Deployed $new: $url serves $version."
out result deployed
summary "\`$new\`" "$version" "deployed; before: \`${previous:-–}\`"
