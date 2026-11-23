# Stack: identities

Every managed identity NEBo uses, with the GitHub (and later AKS) federated credentials that let workflows sign in as it. All of them live in `rg-nebo-mgmt` and are named `mi-nebo-*`. The list is [`identities.yaml`](identities.yaml); `main.tf` only turns it into resources.

**No identity has any rights from this stack.** Roles come only from `core/rbac/grants.yaml` through `rbac.yml`, after the subscription owner approves them. Keeping identities in `rg-nebo-mgmt` means a deployer with Contributor on its own stage group can't change who may sign in as it.

| Group | Lives | Identities |
|---|---|---|
| `shared` | A → end of C | `mi-nebo-rbac` (approved role assignments), `mi-nebo-plan` (read-only plans), `mi-nebo-ops` (wake-up, sleep, guard, reports), `mi-nebo-notify` (email), `mi-nebo-core` (core deployer), `mi-nebo-ci` (image push) |
| `stage-a` | A → end of B | `mi-nebo-stage-a` (deployer), `mi-nebo-cd-a` (Container Apps revisions), `mi-nebo-config` (Ansible), workload: `mi-nebo-menu-aca`, `mi-nebo-vm` |
| `stage-b` | B → end of C | `mi-nebo-stage-b` (deployer), `mi-nebo-cd-b` (Helm), workload: `mi-nebo-aks`, `mi-nebo-kubelet`, `mi-nebo-menu-wi` |
| `stage-c` | C | `mi-nebo-stage-c` (deployer), workload: `mi-nebo-appgw`, `mi-nebo-agic` |

## Who applies it

**You, from your own machine or Azure Cloud Shell.** This is the one stack that doesn't run in GitHub Actions. You need only the two roles the subscription owner gives you in step 1 (`core/scripts/owner/1-Prepare-Subscription.ps1`): Contributor and Storage Blob Data Contributor on `rg-nebo-mgmt`.

```sh
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
core/scripts/ops/bootstrap-state.sh            # once: state storage and core/infra/backend.hcl
cd core/identities
terraform init -backend-config="$(git rev-parse --show-toplevel)/core/infra/backend.hcl"
terraform plan -out identities.tfplan
terraform apply identities.tfplan
terraform output github_variables             # client IDs for the GitHub repository variables
```

Then ask the owner to run `core/scripts/owner/2-Grant-Seed.ps1`. It gives `mi-nebo-rbac` and `mi-nebo-plan` their first rights and puts a ReadOnly lock on `mi-nebo-rbac`. **From then on, any change to `mi-nebo-rbac` fails on that lock, on purpose:** only the owner can change the identity that assigns roles.

## Changing it

- **A new stage:** set its group's `active: true` and apply. Then request its roles in `core/rbac/grants.yaml`.
- **The end of a stage:** first turn the stage off in `core/rbac/grants.yaml` and let the owner approve the removals. Then set `active: false` here and apply. In that order, no role assignment is left pointing at a deleted identity.
- **AKS workload identity (Stage B):** add `namespace:serviceaccount` entries under `kubernetes:` and pass the cluster's OIDC issuer, which contains the tenant ID, so it is never committed:

  ```sh
  terraform apply -var aks_oidc_issuer="$(az aks show -g rg-nebo-stage-b -n <cluster> --query oidcIssuerProfile.issuerUrl -o tsv)"
  ```

**OIDC subjects** use GitHub's ID-based format, e.g. `repo:faza666@56168853/peex-evaluation-nebo-tasks@1459147871:environment:rbac`. A re-created repository with the same name gets new IDs and no access.
