# Stack: core

Shared by every stage: Log Analytics, Azure Monitor workspace, Key Vault, Action Group, budget, the GitHub OIDC identity and Communication Services Email. Lives from Stage A to the end of Stage C. The container registry lives in the same resource group but outside Terraform: `scripts/ops/wake-up.sh` creates it when it is missing.

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-nebo-core` | Every resource is tagged `nebo:stack=core` |
| Log Analytics | `law-nebo-core` | 30-day retention, 0.5 GB/day ingestion cap |
| Azure Monitor workspace | `amw-nebo-core` | Managed Prometheus, from Stage B |
| Key Vault | `kv-nebo-<suffix>` | RBAC mode, no purge protection, so teardown and rebuild work |
| Container registry | `acrnebo<suffix>` | **Not in Terraform.** Created by `wake-up.sh` on first use: Basic, Entra ID only (no admin user, no anonymous pull), tagged `nebo:stack=core`. Repository `menu`, tags `v<version>` and `sha-<7>` |
| Action Group | `ag-nebo-email` | Emails the notification address |
| Budget | `budget-nebo` | Subscription, 50 per month, alerts at 50, 80 and 100% |
| Communication Services | `acs-nebo-<suffix>`, `ecs-nebo-<suffix>` | Azure-managed sender domain, data in Europe |
| GitHub identity | `id-nebo-github` | OIDC for `dev`, `prod`, `main` and pull requests; Reader on the subscription, Contributor on this group, Key Vault Secrets User, AcrPush on the subscription (the registry comes and goes outside Terraform) |

`<suffix>` is the first 6 hex characters of the SHA-256 of the subscription ID, the same as the state storage account.

## Usage

```sh
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
cp notify.auto.tfvars.example notify.auto.tfvars   # then put your address in it; the file is git-ignored
terraform init -backend-config=../backend.hcl
terraform plan -out core.tfplan
terraform apply core.tfplan
```

The outputs (client, tenant and subscription IDs, email endpoint and sender) are not secret and become GitHub repository variables. `acr_name` is the name `wake-up.sh` gives the registry; CI derives the same name from the subscription ID, so it needs no variable.

**Teardown:** the registry blocks `terraform destroy` here, because the provider won't delete a resource group that still holds resources it doesn't manage. Delete it first: `az acr delete -n "$(terraform output -raw acr_name)" --yes`. The notification address is only stored in `notify.auto.tfvars` and the GitHub secret `NOTIFY_EMAIL`.

**OIDC subjects:** GitHub names the repository with immutable IDs in the token subject, e.g. `repo:faza666@56168853/peex-evaluation-nebo-tasks@1459147871:ref:refs/heads/main`, so the federated credentials use that format (`github_owner_id`, `github_repo_id`). A re-created repository with the same name gets a new ID and no access.
