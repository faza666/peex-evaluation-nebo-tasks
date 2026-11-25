# Ops scripts

Tool checks, the state-storage bootstrap, and the wake-up / sleep / status scripts that keep paid compute asleep unless someone is working.

| Script | Purpose |
|---|---|
| `check-tools.sh A\|B\|C` | Checks the tools a stage needs (stages are cumulative) and prints their versions. Exits 1 if a required tool is missing. For Stage A it also checks the `az` extensions, the `gh` `project` scope and `gh` sub-issue support. |
| `bootstrap-state.sh` | One-time setup by the operator, safe to re-run, after the subscription owner has run `core/scripts/owner/1-Prepare-Subscription.ps1`. Creates the Terraform state storage in `rg-nebo-mgmt` (Entra ID only, versioning, soft delete) with one container per state owner (`tfstate-identities`, `-rbac`, `-core`, `-stage-a`, `-stage-b`, `-stage-c`), and writes `core/infra/backend.hcl`. It registers no providers, creates no resource group and assigns no roles. |
| `status.sh [--json]` | Lists every resource tagged `nebo:stack`, with the power state of compute and its `nebo:sleep-after` time. Also a Resource Graph query script for Task 4. |
| `wake-up.sh [--targets all\|vm,aks,appgw] [--hours 1-12]` | Starts the stage's compute, tags it `nebo:sleep-after` = now + N hours (default 4) and waits until it runs. |
| `sleep.sh [--targets all\|vm,aks,appgw] [--no-wait]` | Stops or deallocates the stage's compute, keeping state and configuration. |
| `sleep-guard.sh [--dry-run]` | Puts compute to sleep when it is past its sleep-after time, or has run without one for more than 2 hours. |
| `lib.sh` | Shared helpers, sourced by the scripts above. |

The scripts find resources by the tag `nebo:stack`, so they work in every stage without edits. A failed Azure query stops them with an error rather than being read as "nothing to do". The container registry is permanent (the `core` stack), so none of them touches it.

## Workflows

| Workflow | Trigger | Runs |
|---|---|---|
| `wake-up.yml` | manual (`targets`, `hours`) | `wake-up.sh` |
| `sleep.yml` | manual (`targets`) | `sleep.sh` |
| `sleep-guard.yml` | every hour at :17, or manual (`dry_run`) | `sleep-guard.sh` |

They sign in to Azure through OIDC as `mi-nebo-ops` (no stored credentials), with the tenant and subscription from secrets, and are skipped until the `AZURE_CLIENT_ID_OPS` repository variable exists. `mi-nebo-ops` can start, stop and tag compute in the stage resource groups (`core/rbac/grants.yaml`). From your own machine the scripts can only read: `status.sh` works, while wake-up and sleep need those rights. The workflows share one concurrency group, so a wake-up and a guard run never act at the same time.
