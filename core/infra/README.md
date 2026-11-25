# Stack: core

Shared by every stage, in `rg-nebo-core`: the container registry, Log Analytics, Azure Monitor workspace, Key Vault, the alerts Action Group and an RG budget. Lives from Stage A to the end of Stage C.

The Subscription Owner created the resource group. This stack only fills it, and `terraform.yml` applies it as `mi-nebo-core`. It holds no identities and no role assignments: those live in `core/identities` and `core/rbac/grants.yaml`.

| Resource | Name | Notes |
|---|---|---|
| Container registry | `acrnebo<suffix>` | Basic, **permanent**. Entra ID only: no admin user, and Basic has no anonymous pull. Repository `menu`, tags `v<version>` and `sha-<7>`. `docker-build.yml` pushes as `mi-nebo-ci` |
| Log Analytics | `law-nebo-core` | 30-day retention, 0.5 GB/day ingestion cap |
| Azure Monitor workspace | `amw-nebo-core` | Managed Prometheus, from Stage B |
| Key Vault | `kv-nebo-<suffix>` | RBAC mode, no purge protection, so the end-of-C teardown works. No firewall: Container Apps have no fixed outbound IP, so access is by role only |
| Action Group | `ag-nebo-alerts` | Email to the notification address, and a Teams Workflows webhook once `TEAMS_ALERTS_WEBHOOK_URL` is set |
| Budget | `budget-nebo-core` | This resource group, 10 per month, alerts at 50, 80 and 100% to the Action Group |

`<suffix>` is the first 6 hex characters of the SHA-256 of the subscription ID, the same as the state storage account. Every resource is tagged `nebo:stack=core`. The ones that grants point at also carry `nebo:scope` (`acr`, `kv`, `law`, `amw`), which is how `core/<tag>` scopes in `core/rbac/grants.yaml` find them.

## How it is applied

- **Pull request:** `terraform.yml` runs fmt, validate, TFLint and Trivy, then a read-only plan as `mi-nebo-plan`. The resources that would change are listed in a comment, by address only.
- **Merge to `main`:** `apply (core)` waits in the `core` environment until you approve it. It then plans again with a refresh, as `mi-nebo-core`, and applies.
- **Manual run:** `plan`, `apply` or `destroy` of `core`. Destroy needs `core` typed in the confirm field and ends with a check that nothing tagged `nebo:stack=core` is left.

The notification address and the Teams alerts webhook reach Terraform as `TF_VAR_notify_email` and `TF_VAR_alerts_webhook_url`, from the secrets `NOTIFY_EMAIL` and `TEAMS_ALERTS_WEBHOOK_URL`. Both are sensitive, so plans and logs show neither. They are still visible on the Action Group to anyone with Reader on `rg-nebo-core`, and the webhook URL lets its holder post to the alerts chat.

**On your machine** you can't apply this stack, because `mi-nebo-core` holds its rights. You can still validate it and read its outputs:

```powershell
terraform init "-backend-config=backend.hcl"
terraform validate
terraform output
```

The outputs aren't secret.

**No email service here.** Azure sends the Action Group's alert and budget emails itself. Pipeline notifications go to Teams through the `notify` action, and the same Teams flow emails them from your own mailbox (#22), so NEBo needs no Communication Services.

**Key Vault rebuilds:** `mi-nebo-core` has no rights on the subscription's deleted vaults, so Terraform neither purges nor recovers one. A destroyed vault stays soft-deleted for 7 days, and a rebuild within that time needs a new name or the Subscription Owner's purge.

**Teardown** is the end of Stage C only: destroy `core` from `terraform.yml`, after every stage stack is gone.
