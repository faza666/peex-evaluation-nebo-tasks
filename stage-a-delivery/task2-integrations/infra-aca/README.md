# Stack: aca

The CD target in Stage A, in `rg-nebo-stage-a`: a Container Apps environment with the apps `menu-dev` and `menu-prod`. Lives from Stage A to the end of Stage B.

The Subscription Owner created the resource group. This stack only fills it, and `terraform.yml` applies it as `mi-nebo-stage-a`. It holds no identities and no role assignments: those live in `core/identities` and `core/rbac/grants.yaml`.

| Resource | Name | Notes |
|---|---|---|
| Container Apps environment | `cae-nebo-stage-a` | Consumption only, no VNet. Logs go to `law-nebo-core` |
| Container apps | `menu-dev`, `menu-prod` | Multiple-revision mode, min replicas 0 and max 1, 0.25 vCPU and 0.5 GiB. Public HTTPS ingress to port 8000. Startup and liveness probes on `/health`, readiness on `/ready`. Each pulls from `acrnebo<suffix>` as `mi-nebo-menu-aca` |
| Budget | `budget-nebo-stage-a` | The whole resource group, so it covers the `vm` stack too. 5 per month, alerts at 50, 80 and 100% to the core Action Group |

Every resource is tagged `nebo:stack=aca`.

## Who changes what

- **This stack creates the apps.** A new app starts with `menu:sha-<7>`, the image `docker-build.yml` pushed for the commit `terraform.yml` applies. That commit comes in as `TF_VAR_commit`.
- **[`cd.yml`](../../../.github/workflows/cd.yml) owns the revisions after that.** It sets the image, names the revision and moves the traffic. Terraform ignores those three, so a later apply doesn't undo a deploy. Any other change to the template, such as a probe, makes a new revision with the image that is running. That revision gets no traffic until the next deploy moves traffic to a new revision.
- **The database is SQLite inside the container.** Each replica migrates and seeds its own copy when it starts, so data doesn't outlive a replica. That is enough for the smoke test and the demo.

## Rights it relies on

All of these are in `core/rbac/grants.yaml`, approved with the Stage A grants:

| Identity | Role | For |
|---|---|---|
| `mi-nebo-stage-a` | Contributor on `rg-nebo-stage-a` | the environment, the apps and the budget |
| `mi-nebo-stage-a` | Log Analytics Contributor on `law-nebo-core` | linking the environment to the workspace, which reads its key |
| `mi-nebo-stage-a` | Managed Identity Operator on `mi-nebo-menu-aca` | attaching the identity to the apps |
| `mi-nebo-stage-a` | Reader on `rg-nebo-core` | the Action Group, for the budget |
| `mi-nebo-menu-aca` | AcrPull on the registry, Key Vault Secrets User on the vault | pulling images; secrets once the app needs any |
| `mi-nebo-cd-a` | Container Apps Contributor on `rg-nebo-stage-a` | `cd.yml`: revisions and traffic |

## How it is applied

- **Pull request:** `terraform.yml` runs fmt, validate, TFLint and Trivy, then a read-only plan as `mi-nebo-plan`.
- **Merge to `main`:** `apply (aca)` waits in the `stage-a` environment until you approve it. **On the first apply, approve it only after `docker-build` has pushed the image for the same commit.** Otherwise the apps' first revisions have nothing to pull and the apply fails.
- **Manual run:** `plan`, `apply` or `destroy` of `aca`. Destroy needs `aca` typed in the confirm field and ends with a check that nothing tagged `nebo:stack=aca` is left.

Locally you can only validate it:

```sh
terraform init -backend=false && terraform validate
```

**Cost:** nothing while idle. Min replicas 0 means an app has no replicas until a request arrives, and the consumption plan's monthly free grant covers the rest. `sleep` and `wake-up` leave the apps alone.

**Teardown** is at the end of Stage B: destroy `aca` from `terraform.yml`.
