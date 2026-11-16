#!/usr/bin/env bash
# Shared helpers for the NEBo ops scripts. Source it; don't run it.
#
# Every NEBo resource carries the tag nebo:stack=<name>, so the scripts find what exists in
# the current stage with one Azure Resource Graph query and need no edits between stages.
# Compute that can sleep: VMs (deallocate), AKS clusters (stop), Application Gateways (stop).
# The container registry (acr) has no sleep state: wake-up creates it and sleep deletes it.

TAG_STACK="nebo:stack"
TAG_SLEEP_AFTER="nebo:sleep-after"
TAG_FIRST_SEEN="nebo:first-seen-awake"
CORE_RG="rg-nebo-core"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }

# Append markdown to the GitHub job summary when running in Actions.
summary() {
  if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"; fi
}

# Print a warning, as an annotation in Actions.
warn() {
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then echo "::warning::$*"; else log "WARNING: $*"; fi
}

now_epoch() { date -u +%s; }
iso_in_hours() { date -u -d "+$1 hours" +%Y-%m-%dT%H:%MZ; }
# Epoch seconds of an ISO time, or nothing if it doesn't parse (e.g. the tag says "asleep").
to_epoch() { date -u -d "$1" +%s 2>/dev/null || true; }

# All tagged resources as JSON lines:
# {id, name, type, computeKind, resourceGroup, stack, power, sleepAfter, firstSeen}
# computeKind is vm, aks, appgw or other; power is running, stopped, transitioning or "" (not compute).
nebo_resources() {
  local query
  query=$(
    cat <<EOF
Resources
| where isnotempty(tags['$TAG_STACK'])
| extend computeKind = case(
    type =~ 'microsoft.compute/virtualmachines', 'vm',
    type =~ 'microsoft.containerservice/managedclusters', 'aks',
    type =~ 'microsoft.network/applicationgateways', 'appgw',
    'other')
| extend rawPower = case(
    computeKind == 'vm', tostring(properties.extended.instanceView.powerState.code),
    computeKind == 'aks', tostring(properties.powerState.code),
    computeKind == 'appgw', tostring(properties.operationalState),
    '')
| extend power = case(
    rawPower in~ ('PowerState/running', 'Running'), 'running',
    rawPower in~ ('PowerState/deallocated', 'PowerState/stopped', 'Stopped'), 'stopped',
    isempty(rawPower), '',
    'transitioning')
| project id, name, type = tostring(split(type, '/')[1]), computeKind, resourceGroup, stack = tostring(tags['$TAG_STACK']), power,
    sleepAfter = tostring(tags['$TAG_SLEEP_AFTER']), firstSeen = tostring(tags['$TAG_FIRST_SEEN'])
| order by stack asc, computeKind asc, name asc
EOF
  )
  az graph query -q "$query" --first 1000 --only-show-errors -o json | jq -c '.data[]'
}

# Compute resources only, optionally limited to the kinds in $1 (comma-separated, or "all").
nebo_compute() {
  local targets=${1:-all}
  nebo_resources | jq -c --arg t "$targets" '
    select(.computeKind != "other")
    | select($t == "all" or (.computeKind as $k | ($t | split(",") | index($k)) != null))'
}

# Read JSON lines from a variable into the named array; empty input gives an empty array.
# Callers capture the query first (rows=$(nebo_compute ...)) so a failed query stops the script.
to_array() { # array-name "$rows"
  local -n _arr=$1
  _arr=()
  [[ -n $2 ]] && mapfile -t _arr <<<"$2"
  return 0
}

# Validate a --targets value: "all" or a comma-separated list of vm, aks, appgw, acr.
check_targets() {
  [[ $1 == all || $1 =~ ^(vm|aks|appgw|acr)(,(vm|aks|appgw|acr))*$ ]] ||
    { log "ERROR: --targets must be 'all' or a comma-separated list of vm, aks, appgw, acr (got '$1')"; return 1; }
}

# True if a --targets value includes the given kind.
targets_include() { # targets kind
  [[ $1 == all || ,$1, == *,$2,* ]]
}

# The suffix shared with the Terraform stacks, bootstrap-state.sh and ci.yml:
# the first 6 hex characters of sha256(subscription ID).
nebo_suffix() {
  local sub
  sub=$(az account show --query id -o tsv --only-show-errors)
  printf '%s' "$sub" | sha256sum | cut -c1-6
}

# The container registry lives outside Terraform and only while someone works: wake-up
# creates it, sleep deletes it with its images. CI rebuilds any image from its commit on main.
registry_name() { echo "acrnebo$(nebo_suffix)"; }

registry_exists() { # name
  az acr show --resource-group "$CORE_RG" --name "$1" --only-show-errors -o none 2>/dev/null
}

# Create the registry if it is missing: Basic, Entra ID only, tagged with the core stack.
# With a sleep-after time, tag it so sleep-guard deletes it then, like compute it puts to sleep.
ensure_registry() { # [sleep-after]
  local name sleep_after=${1:-} id
  local tags=("$TAG_STACK=core")
  name=$(registry_name)
  if [[ -n $sleep_after ]]; then
    tags+=("$TAG_SLEEP_AFTER=$sleep_after")
  fi
  if registry_exists "$name"; then
    log "$name: registry exists"
    if [[ -n $sleep_after ]]; then
      id=$(az acr show --resource-group "$CORE_RG" --name "$name" --query id -o tsv --only-show-errors)
      set_tags "$id" "$TAG_SLEEP_AFTER=$sleep_after" "$TAG_FIRST_SEEN="
    fi
  else
    log "$name: creating the container registry (Basic) in $CORE_RG"
    az acr create --resource-group "$CORE_RG" --name "$name" --sku Basic --admin-enabled false \
      --tags "${tags[@]}" --only-show-errors -o none
    log "$name: created (empty: run ci.yml on main to rebuild and push the current image)"
    summary "Created the container registry \`$name\`. It starts empty: run **ci** on \`main\` to push the current image."
  fi
  if [[ -n $sleep_after ]]; then
    log "$name: sleep-guard deletes it after $sleep_after"
  fi
}

# Delete the registry entirely, images included.
delete_registry() {
  local name
  name=$(registry_name)
  if ! registry_exists "$name"; then
    log "$name: no registry to delete"
    return 0
  fi
  log "$name: deleting the container registry and its images"
  az acr delete --resource-group "$CORE_RG" --name "$name" --yes --only-show-errors -o none
  log "$name: deleted"
  summary "Deleted the container registry \`$name\` and its images."
}

set_tags() { # resource-id key=value...
  local id=$1
  shift
  az tag update --resource-id "$id" --operation Merge --tags "$@" --only-show-errors -o none
}

start_resource() { # json line
  local id name rg
  id=$(jq -r .id <<<"$1") name=$(jq -r .name <<<"$1") rg=$(jq -r .resourceGroup <<<"$1")
  case $(jq -r .computeKind <<<"$1") in
    vm) az vm start --ids "$id" --no-wait --only-show-errors ;;
    aks) az aks start -g "$rg" -n "$name" --no-wait --only-show-errors ;;
    appgw) az network application-gateway start --ids "$id" --no-wait --only-show-errors ;;
  esac
}

stop_resource() { # json line
  local id name rg
  id=$(jq -r .id <<<"$1") name=$(jq -r .name <<<"$1") rg=$(jq -r .resourceGroup <<<"$1")
  case $(jq -r .computeKind <<<"$1") in
    vm) az vm deallocate --ids "$id" --no-wait --only-show-errors ;;
    aks) az aks stop -g "$rg" -n "$name" --no-wait --only-show-errors ;;
    appgw) az network application-gateway stop --ids "$id" --no-wait --only-show-errors ;;
  esac
}

# Current power state of one resource, read directly (Resource Graph can lag by minutes).
power_now() { # json line
  local id name rg
  id=$(jq -r .id <<<"$1") name=$(jq -r .name <<<"$1") rg=$(jq -r .resourceGroup <<<"$1")
  case $(jq -r .computeKind <<<"$1") in
    vm) az vm get-instance-view --ids "$id" --only-show-errors \
      --query "instanceView.statuses[?starts_with(code,'PowerState/')].code | [0]" -o tsv ;;
    aks) az aks show -g "$rg" -n "$name" --only-show-errors \
      --query "join('/', [powerState.code, provisioningState])" -o tsv ;;
    appgw) az network application-gateway show --ids "$id" --only-show-errors \
      --query operationalState -o tsv ;;
  esac
}

# Wait until every resource in the JSON lines on stdin reports the wanted state.
wait_for() { # running|stopped timeout-seconds
  local want=$1 timeout=$2 deadline line state ok
  deadline=$(($(now_epoch) + timeout))
  mapfile -t lines
  while :; do
    ok=1
    for line in "${lines[@]}"; do
      state=$(power_now "$line")
      case $want in
        running) [[ $state =~ ^(PowerState/running|Running/Succeeded|Running)$ ]] || ok=0 ;;
        stopped) [[ $state =~ ^(PowerState/deallocated|Stopped/Succeeded|Stopped)$ ]] || ok=0 ;;
      esac
    done
    ((ok)) && return 0
    (($(now_epoch) > deadline)) && { log "ERROR: not all resources are $want after ${timeout}s"; return 1; }
    sleep 20
  done
}
