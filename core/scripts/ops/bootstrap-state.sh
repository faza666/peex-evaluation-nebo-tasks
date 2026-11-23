#!/usr/bin/env bash
# Create the storage for Terraform state in rg-nebo-mgmt (safe to re-run; existing resources are kept).
#
# Usage: core/scripts/ops/bootstrap-state.sh
#
# Run it as the operator, after the subscription owner has run core/scripts/owner/1-Prepare-Subscription.ps1.
# That script creates the resource groups and gives you Contributor and Storage Blob Data Contributor on
# rg-nebo-mgmt; nothing here needs more. Uses the current `az login` session and subscription. It:
#   1. checks that rg-nebo-mgmt exists,
#   2. creates a storage account that accepts Entra ID sign-in only (shared keys off, TLS 1.2, HTTPS only,
#      no public blobs) with blob versioning and 7-day soft delete,
#   3. creates one container per state owner: tfstate-identities, -rbac, -core, -stage-a, -stage-b, -stage-c,
#      through the management plane, so no data-plane role has to propagate first,
#   4. writes core/infra/backend.hcl, which every stack passes to `terraform init -backend-config`.
#      Each stack names its own container and key in its backend block.
#
# It registers no resource providers, creates no resource group and assigns no roles: the owner does those.
set -euo pipefail

RG=rg-nebo-mgmt
CONTAINERS=(tfstate-identities tfstate-rbac tfstate-core tfstate-stage-a tfstate-stage-b tfstate-stage-c)
TAGS=("nebo:stack=state")
REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
BACKEND_FILE="$REPO_ROOT/core/infra/backend.hcl"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

sub_id=$(az account show --query id -o tsv)
sub_name=$(az account show --query name -o tsv)
# Same suffix as the Terraform stacks: the first 6 hex characters of sha256(subscription ID).
suffix=$(printf '%s' "$sub_id" | sha256sum | cut -c1-6)
account="stnebotf${suffix}"

# 1. The resource group comes from the subscription owner.
if ! location=$(az group show -n "$RG" --query location -o tsv 2>/dev/null); then
  log "ERROR: $RG not found in '$sub_name'. The subscription owner runs core/scripts/owner/1-Prepare-Subscription.ps1 first."
  exit 1
fi
log "Subscription: $sub_name, resource group: $RG ($location), storage account: $account"

# 2. Storage account.
security=(--min-tls-version TLS1_2 --allow-blob-public-access false --allow-shared-key-access false --https-only true)
if az storage account show -n "$account" -g "$RG" -o none 2>/dev/null; then
  az storage account update -n "$account" -g "$RG" "${security[@]}" -o none
  log "Storage account $account: exists, security settings enforced"
else
  az storage account create -n "$account" -g "$RG" -l "$location" --sku Standard_LRS --kind StorageV2 \
    "${security[@]}" --tags "${TAGS[@]}" -o none
  log "Storage account $account: created"
fi
az storage account blob-service-properties update --account-name "$account" -g "$RG" \
  --enable-versioning true --enable-delete-retention true --delete-retention-days 7 \
  --enable-container-delete-retention true --container-delete-retention-days 7 -o none
log "Blob versioning and 7-day soft delete: on"

# 3. Containers, through the management plane (Contributor is enough).
for container in "${CONTAINERS[@]}"; do
  if az storage container-rm show -n "$container" --storage-account "$account" -g "$RG" -o none 2>/dev/null; then
    log "Container $container: exists"
  else
    az storage container-rm create -n "$container" --storage-account "$account" -g "$RG" \
      --public-access off -o none
    log "Container $container: created"
  fi
done

# 4. Backend config shared by every stack (each stack sets its own container_name and key).
cat >"$BACKEND_FILE" <<EOF
# Written by core/scripts/ops/bootstrap-state.sh. Every stack passes it to init:
#   terraform init -backend-config="\$(git rev-parse --show-toplevel)/core/infra/backend.hcl"
# and sets its own container (tfstate-<owner>) and state file name in its backend block.
resource_group_name  = "$RG"
storage_account_name = "$account"
use_azuread_auth     = true
EOF
log "Wrote ${BACKEND_FILE#"$REPO_ROOT"/}"
