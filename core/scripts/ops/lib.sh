#!/usr/bin/env bash
# Shared helpers for the NEBo ops scripts. Source it; don't run it.
#
# Every NEBo resource carries the tag nebo:stack=<name>, so the scripts find what exists in
# the current stage with one Azure Resource Graph query and need no edits between stages.
# Compute that can sleep: VMs (deallocate), AKS clusters (stop), Application Gateways (stop) and
# Container Apps (stop: a stopped app serves nothing, so no request can start it again).
# The container registry is permanent (core stack), so these scripts never touch it.

TAG_STACK="nebo:stack"
ACA_API="2025-01-01" # Microsoft.App API version for a Container App's status, start and stop (no az command)
TAG_SLEEP_AFTER="nebo:sleep-after"
TAG_FIRST_SEEN="nebo:first-seen-awake"

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
# computeKind is vm, aks, appgw, aca or other; power is running, stopped, transitioning or "" (not compute).
nebo_resources() {
  local query row power
  query=$(
    cat <<EOF
Resources
| where isnotempty(tags['$TAG_STACK'])
| extend computeKind = case(
    type =~ 'microsoft.compute/virtualmachines', 'vm',
    type =~ 'microsoft.containerservice/managedclusters', 'aks',
    type =~ 'microsoft.network/applicationgateways', 'appgw',
    type =~ 'microsoft.app/containerapps', 'aca',
    'other')
| extend rawPower = case(
    computeKind == 'vm', tostring(properties.extended.instanceView.powerState.code),
    computeKind == 'aks', tostring(properties.powerState.code),
    computeKind == 'appgw', tostring(properties.operationalState),
    computeKind == 'aca', tostring(properties.runningStatus),
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
  # Resource Graph may not carry a Container App's runningStatus; then it is read from the app itself.
  az graph query -q "$query" --first 1000 --only-show-errors -o json | jq -c '.data[]' |
    while IFS= read -r row; do
      if [[ $(jq -r '"\(.computeKind)/\(.power)"' <<<"$row") == aca/ ]]; then
        power=$(aca_power "$(jq -r .id <<<"$row")") || exit 1 # a failed read stops the caller
        row=$(jq -c --arg p "$power" '.power = $p' <<<"$row")
      fi
      printf '%s\n' "$row"
    done
}

# A Container App's runningStatus, read directly: Running, Stopped, or a passing state such as Progressing.
aca_status() { # resource-id
  az rest --method get --url "https://management.azure.com$1?api-version=$ACA_API" \
    --query properties.runningStatus -o tsv --only-show-errors
}

aca_power() { # resource-id -> running | stopped | transitioning
  local status
  status=$(aca_status "$1") || return 1
  case $status in
    Running) echo running ;;
    Stopped) echo stopped ;;
    *) echo transitioning ;;
  esac
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

# Validate a --targets value: "all" or a comma-separated list of vm, aks, appgw, aca.
check_targets() {
  [[ $1 == all || $1 =~ ^(vm|aks|appgw|aca)(,(vm|aks|appgw|aca))*$ ]] ||
    { log "ERROR: --targets must be 'all' or a comma-separated list of vm, aks, appgw, aca (got '$1')"; return 1; }
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
    aca) az rest --method post --url "https://management.azure.com$id/start?api-version=$ACA_API" \
      --only-show-errors -o none ;; # accepted at once; wait_for follows it
  esac
}

stop_resource() { # json line
  local id name rg
  id=$(jq -r .id <<<"$1") name=$(jq -r .name <<<"$1") rg=$(jq -r .resourceGroup <<<"$1")
  case $(jq -r .computeKind <<<"$1") in
    vm) az vm deallocate --ids "$id" --no-wait --only-show-errors ;;
    aks) az aks stop -g "$rg" -n "$name" --no-wait --only-show-errors ;;
    appgw) az network application-gateway stop --ids "$id" --no-wait --only-show-errors ;;
    aca) az rest --method post --url "https://management.azure.com$id/stop?api-version=$ACA_API" \
      --only-show-errors -o none ;;
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
    aca) aca_status "$id" ;;
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
