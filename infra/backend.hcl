# Written by scripts/ops/bootstrap-state.sh. Every stack runs:
#   terraform init -backend-config=../backend.hcl
# and sets its own state file name with `key` in its backend block.
resource_group_name  = "rg-nebo-tfstate"
storage_account_name = "stnebotf6ae61a"
container_name       = "tfstate"
use_azuread_auth     = true
