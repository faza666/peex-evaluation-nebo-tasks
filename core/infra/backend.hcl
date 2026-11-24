# Written by core/scripts/ops/bootstrap-state.sh. Every stack passes it to init:
#   terraform init -backend-config="$(git rev-parse --show-toplevel)/core/infra/backend.hcl"
# and sets its own container (tfstate-<owner>) and state file name in its backend block.
resource_group_name  = "rg-nebo-mgmt"
storage_account_name = "stnebotf195ba5"
use_azuread_auth     = true
