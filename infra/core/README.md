# Stack: core

Shared by every stage: Log Analytics, Azure Monitor workspace, Key Vault, Action Group, budget, the GitHub OIDC identity and Communication Services Email. Lives from Stage A to the end of Stage C. The container registry joins it in A1, when the first images are pushed.

| Resource | Name | Notes |
|---|---|---|
| Resource group | `rg-nebo-core` | Every resource is tagged `nebo:stack=core` |
| Log Analytics | `law-nebo-core` | 30-day retention, 0.5 GB/day ingestion cap |
| Azure Monitor workspace | `amw-nebo-core` | Managed Prometheus, from Stage B |
| Key Vault | `kv-nebo-<suffix>` | RBAC mode, no purge protection, so teardown and rebuild work |
| Container registry | `acrnebo<suffix>` | Added in A1 (Basic, admin account off), not created yet |
| Action Group | `ag-nebo-email` | Emails the notification address |
| Budget | `budget-nebo` | Subscription, 50 per month, alerts at 50, 80 and 100% |
| Communication Services | `acs-nebo-<suffix>`, `ecs-nebo-<suffix>` | Azure-managed sender domain, data in Europe |
| GitHub identity | `id-nebo-github` | OIDC for `dev`, `prod`, `main` and pull requests; Reader on the subscription, Contributor on this group, Key Vault Secrets User (AcrPush from A1) |

`<suffix>` is the first 6 hex characters of the SHA-256 of the subscription ID, the same as the state storage account.

## Usage

```sh
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
cp notify.auto.tfvars.example notify.auto.tfvars   # then put your address in it; the file is git-ignored
terraform init -backend-config=../backend.hcl
terraform plan -out core.tfplan
terraform apply core.tfplan
```

The outputs (client, tenant and subscription IDs, email endpoint and sender) are not secret and become GitHub repository variables. The notification address is only stored in `notify.auto.tfvars` and the GitHub secret `NOTIFY_EMAIL`.

**OIDC subjects:** GitHub names the repository with immutable IDs in the token subject, e.g. `repo:faza666@56168853/peex-evaluation-nebo-tasks@1459147871:ref:refs/heads/main`, so the federated credentials use that format (`github_owner_id`, `github_repo_id`). A re-created repository with the same name gets a new ID and no access.
