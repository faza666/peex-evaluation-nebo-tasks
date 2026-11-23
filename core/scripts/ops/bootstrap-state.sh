#!/usr/bin/env bash
# Create the storage for Terraform state (safe to re-run; existing resources are left as they are).
#
# Usage: core/scripts/ops/bootstrap-state.sh
#
# Uses the current `az login` session and subscription. It:
#   1. checks that you hold Owner on the subscription (Terraform creates role assignments),
#   2. registers the resource providers every NEBo stack needs,
#   3. creates resource group rg-nebo-tfstate and a storage account that accepts Entra ID only
#      (shared keys off, TLS 1.2, no public blobs, versioning and 7-day soft delete),
#   4. gives you Storage Blob Data Contributor on it and creates the `tfstate` container,
#   5. writes core/infra/backend.hcl, which every stack passes to `terraform init -backend-config`.
set -euo pipefail

LOCATION=${LOCATION:-swedencentral}
RG=rg-nebo-tfstate
CONTAINER=tfstate
TAGS=("nebo:stack=tfstate")
PROVIDERS=(
  Microsoft.App Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.KeyVault
  Microsoft.OperationalInsights Microsoft.Insights Microsoft.Monitor Microsoft.AlertsManagement
  Microsoft.Communication Microsoft.Network Microsoft.Compute Microsoft.Storage
  Microsoft.ManagedIdentity Microsoft.Consumption
)
REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
BACKEND_FILE="$REPO_ROOT/core/infra/backend.hcl"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

sub_id=$(az account show --query id -o tsv)
sub_name=$(az account show --query name -o tsv)
user_oid=$(az ad signed-in-user show --query id -o tsv)
# Same suffix as the Terraform stacks: the first 6 hex characters of sha256(subscription ID).
suffix=$(printf '%s' "$sub_id" | sha256sum | cut -c1-6)
account="stnebotf${suffix}"
log "Subscription: $sub_name, region: $LOCATION, storage account: $account"

# 1. Owner check (direct, inherited or through a group).
roles=$(az role assignment list --assignee "$user_oid" --scope "/subscriptions/$sub_id" \
  --include-inherited --include-groups --query "[].roleDefinitionName" -o tsv)
if ! grep -qx "Owner" <<<"$roles"; then
  log "ERROR: you need Owner on the subscription (found: ${roles//$'\n'/, })"
  exit 1
fi
log "Owner on the subscription: yes"

# 2. Resource providers.
pending=()
for p in "${PROVIDERS[@]}"; do
  state=$(az provider show -n "$p" --query registrationState -o tsv)
  if [[ $state != Registered ]]; then
    az provider register -n "$p" --only-show-errors >/dev/null
    pending+=("$p")
  fi
done
if ((${#pending[@]} == 0)); then
  log "Resource providers: all ${#PROVIDERS[@]} already registered"
else
  log "Registering: ${pending[*]}"
  for _ in $(seq 60); do
    left=()
    for p in "${pending[@]}"; do
      [[ $(az provider show -n "$p" --query registrationState -o tsv) == Registered ]] || left+=("$p")
    done
    ((${#left[@]} == 0)) && break
    sleep 10
  done
  ((${#left[@]} == 0)) || { log "ERROR: still registering after 10 min: ${left[*]}"; exit 1; }
  log "Resource providers: registered"
fi

# 3. Resource group and storage account.
if [[ $(az group exists -n "$RG") == true ]]; then
  log "Resource group $RG: exists"
else
  az group create -n "$RG" -l "$LOCATION" --tags "${TAGS[@]}" -o none
  log "Resource group $RG: created"
fi

security=(--min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false --https-only true)
if az storage account show -n "$account" -g "$RG" -o none 2>/dev/null; then
  az storage account update -n "$account" -g "$RG" "${security[@]}" -o none
  log "Storage account $account: exists, security settings enforced"
else
  az storage account create -n "$account" -g "$RG" -l "$LOCATION" --sku Standard_LRS --kind StorageV2 \
    "${security[@]}" --tags "${TAGS[@]}" -o none
  log "Storage account $account: created"
fi
az storage account blob-service-properties update --account-name "$account" -g "$RG" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 7 \
  --enable-container-delete-retention true --container-delete-retention-days 7 -o none
log "Blob versioning and 7-day soft delete: on"

# 4. Data-plane access for you, then the container (role assignments can take a few minutes).
account_id=$(az storage account show -n "$account" -g "$RG" --query id -o tsv)
role="Storage Blob Data Contributor"
if [[ -n $(az role assignment list --assignee "$user_oid" --role "$role" --scope "$account_id" --query "[].id" -o tsv) ]]; then
  log "$role for you: exists"
else
  az role assignment create --assignee-object-id "$user_oid" --assignee-principal-type User \
    --role "$role" --scope "$account_id" -o none
  log "$role for you: assigned"
fi
for attempt in $(seq 30); do
  if az storage container create -n "$CONTAINER" --account-name "$account" --auth-mode login -o none 2>/dev/null; then
    break
  fi
  ((attempt == 30)) && { log "ERROR: container still not creatable after 5 min (role propagation?)"; exit 1; }
  sleep 10
done
log "Container $CONTAINER: ready"

# 5. Backend config shared by every stack (each stack sets its own key).
cat >"$BACKEND_FILE" <<EOF
# Written by core/scripts/ops/bootstrap-state.sh. Every stack passes it to init:
#   terraform init -backend-config="\$(git rev-parse --show-toplevel)/core/infra/backend.hcl"
# and sets its own state file name with \`key\` in its backend block.
resource_group_name  = "$RG"
storage_account_name = "$account"
container_name       = "$CONTAINER"
use_azuread_auth     = true
EOF
log "Wrote ${BACKEND_FILE#"$REPO_ROOT"/}"
