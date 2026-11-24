# Stack: rbac

Every NEBo role assignment, and nothing else. The list is [`grants.yaml`](grants.yaml); `main.tf` checks it and resolves its names to IDs. Only [`rbac.yml`](../../.github/workflows/rbac.yml) applies it, and only after the subscription owner approves the run in GitHub. No other stack may contain a role assignment.

## How a change goes through

1. **Pull request** that edits `grants.yaml`. `rbac.yml` plans as `mi-nebo-plan` (read-only) and comments the change list: ＋ add / － remove, identity, role and scope, by name only.
2. **Merge.** The run on `main` plans again. If anything changes, it posts an approval card into the Teams chat between you and the subscription owner (workflow `NEBo approvals`, secret `TEAMS_APPROVALS_WEBHOOK_URL`).
3. **The owner approves:** **Review and approve** on the card → **Review deployments** → **Approve**. The `apply` job then signs in as `mi-nebo-rbac`, plans again, and applies only if the list is exactly the one in the card. A result card follows: applied, or not applied and why.

Every Monday the workflow also checks for drift. If an assignment was removed or changed outside Terraform, the same card asks to restore it.

## Guards

| Guard | Where |
|---|---|
| Owner, User Access Administrator and Role Based Access Control Administrator are refused | `main.tf` (grants.yaml), then `rbac-changes.sh` on the plan |
| Scopes only inside the five NEBo resource groups; never on `mi-nebo-rbac` or the `identities`/`rbac` state containers | `main.tf`, then `rbac-changes.sh` on the real scopes |
| Nothing is applied without the owner: the `rbac` environment has the owner as required reviewer, prevent self-review on, `main` only, and no admin bypass | GitHub; the `request` job checks these rules and stops if one is missing |
| The owner approves what they saw: the card's list has a digest, and `apply` stops if its own plan differs | `rbac.yml` |
| Only `mi-nebo-rbac` can assign roles. Its only federated credential trusts `environment:rbac`, and a ReadOnly lock from the owner keeps anyone from adding another | `core/identities`, `2-Grant-Seed.ps1` |
| Nothing secret or identifying is published: no plan file is uploaded, and the change list has names, not IDs | `rbac.yml`, `rbac-changes.sh` |

## Scopes

Each grant in `grants.yaml` is `<built-in role> @ <scope>`, under the identity (or `operator`) that receives it.

| Scope | Means | Example |
|---|---|---|
| `rg:<group>` | a NEBo resource group: `mgmt`, `core`, `stage-a`, `stage-b`, `stage-c` | `Reader @ rg:core` |
| `container:<name>` | a state container: `tfstate-core`, `tfstate-stage-a`, `-stage-b`, `-stage-c` | `Storage Blob Data Contributor @ container:tfstate-core` |
| `mi:<identity>` | a managed identity in `rg-nebo-mgmt` | `Managed Identity Operator @ mi:mi-nebo-vm` |
| `<group>/<tag>` | the one resource in `rg-nebo-<group>` that its stack tagged `nebo:scope = "<tag>"` | `AcrPush @ core/acr` |

A grant on a resource goes in with the work item that creates the resource: tag it in its stack, apply, then add the grant.

## Who can do what here

- **`mi-nebo-plan`** (pull requests and `main`) has Reader on the five groups and Storage Blob Data Reader on the state account, both seed grants. It can plan, but not lock the state, so it plans with `-lock=false`.
- **`mi-nebo-rbac`** (environment `rbac` only) has Role Based Access Control Administrator on the five groups and Storage Blob Data Contributor on `tfstate-rbac`, both seed grants.
- **You** can't apply this stack: you have no right to assign roles. Locally, `terraform init -backend=false && terraform validate` is all there is.

## One-time setup of the `rbac` environment

Settings → Environments → `rbac`:
- Required reviewers: the subscription owner. Prevent self-review: on.
- Deployment branches: selected branches, `main`.
- Allow administrators to bypass: off.

The `request` job reads these rules before every request and stops if one is missing.
