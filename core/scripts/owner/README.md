# Scripts for the subscription owner

These scripts are for **the owner of the Azure subscription NEBo runs in**. NEBo is a learning project: a small web app and its platform, deployed from this public repository by GitHub Actions. The person running it, the *operator*, has no Owner rights and no subscription-wide rights. Nobody needs, or touches, Microsoft Entra ID.

You do two short setup steps. After that, **every role assignment NEBo needs arrives as a request for your approval**: a card in your Teams approvals channel links to a GitHub run that lists the exact roles, and nothing is assigned until you press **Approve**.

## What you run, and when

| # | Who | What | Script |
|---|---|---|---|
| 1 | **You** | Create the five NEBo resource groups and give the operator Contributor and Storage Blob Data Contributor on `rg-nebo-mgmt` | [`1-Prepare-Subscription.ps1`](1-Prepare-Subscription.ps1) |
| 2 | Operator | Create the Terraform state storage and the managed identities in `rg-nebo-mgmt` | (`core/scripts/ops/bootstrap-state.sh`, `core/identities`) |
| 3 | **You** | Give the two workflow identities their first rights, and lock the one that assigns roles | [`2-Grant-Seed.ps1`](2-Grant-Seed.ps1) |
| – | **You**, any time | See every NEBo resource group, role assignment and lock (read-only) | [`Show-NeboAccess.ps1`](Show-NeboAccess.ps1) |
| – | **You**, at the end | Remove everything NEBo created | [`9-Remove-Nebo.ps1`](9-Remove-Nebo.ps1) |

**Before you run any of them,** read what it does:
- `Get-Help ./<script>.ps1 -Full` prints its purpose, every step, the methods it uses and how to undo it.
- Run it with `-WhatIf` first to see each change without making it.

## How to run them

- **Requirements:** PowerShell 7.2 or later and the Az modules (`Install-Module Az -Scope CurrentUser`). Azure Cloud Shell (PowerShell) already has both.
- **Sign-in:** each script starts with `Connect-AzAccount`, the Az-module equivalent of `az login`, unless you are already signed in to that subscription. It then checks that the active subscription is the one you passed, and stops before changing anything if it isn't.
- **Re-runs are safe.** Existing resource groups, role assignments and locks are reported and skipped.
- **Your rights:** Owner on the subscription. No Entra ID role is needed.

```powershell
# Step 1. The operator sends you their object ID:
#   az ad signed-in-user show --query id -o tsv
./1-Prepare-Subscription.ps1 -SubscriptionId <subscription-id> -OperatorObjectId <object-id> -WhatIf
./1-Prepare-Subscription.ps1 -SubscriptionId <subscription-id> -OperatorObjectId <object-id>

# Step 3, after the operator says the identities exist:
./2-Grant-Seed.ps1 -SubscriptionId <subscription-id> -WhatIf
./2-Grant-Seed.ps1 -SubscriptionId <subscription-id>

# Any time:
./Show-NeboAccess.ps1 -SubscriptionId <subscription-id> -OperatorObjectId <object-id>
```

## What gets created and granted

**Resource groups.** Empty groups cost nothing. Each is tagged `nebo:rg=<stage>`.

| Group | Holds | Lives |
|---|---|---|
| `rg-nebo-mgmt` | Terraform state, every managed identity (`mi-nebo-*`) | until the end of the project |
| `rg-nebo-core` | shared services: container registry, Key Vault, logs, email | until the end |
| `rg-nebo-stage-a` | Container Apps and a small VM | stages A and B |
| `rg-nebo-stage-b` | AKS | stages B and C |
| `rg-nebo-stage-c` | App Gateway | stage C |

**Grants made by these scripts.** Only built-in roles, never custom roles or conditions, never at subscription scope.

| To | Role | Scope | Why |
|---|---|---|---|
| operator | Contributor | `rg-nebo-mgmt` | create the state storage account and the managed identities |
| operator | Storage Blob Data Contributor | `rg-nebo-mgmt` | read and write Terraform state; the account accepts sign-in tokens only, no keys |
| `mi-nebo-rbac` | Role Based Access Control Administrator | the five groups | the identity the approval workflow uses to assign roles |
| `mi-nebo-rbac` | Storage Blob Data Contributor | container `tfstate-rbac` | its own Terraform state |
| `mi-nebo-plan` | Reader | the five groups | read-only previews of every change, before you approve it |
| `mi-nebo-plan` | Storage Blob Data Reader | the state account | read the Terraform state for those previews |

Some notes on these choices:
- **Role Based Access Control Administrator** is the narrowest built-in role that can assign roles. It can create and delete role assignments, and read; it cannot create role definitions. Contributor cannot assign roles at all.
- **`mi-nebo-rbac` gets a ReadOnly lock (`nebo-approval-guard`).** The operator holds Contributor on `rg-nebo-mgmt`; without the lock they could add a sign-in trust to that identity and use it without your approval. Contributor can't remove locks, and the lock doesn't stop the identity from signing in.
- **No Entra ID lookups.** Role assignments go through the Azure Resource Manager REST API with an explicit principal type, so nothing is looked up in the directory.

## How approvals reach you

1. The operator changes the list of grants in `core/rbac/grants.yaml` through a pull request.
2. After it merges, the workflow `rbac.yml` computes the exact changes (`+`/`−`, identity, role, scope) as the read-only `mi-nebo-plan`, and posts a card to your Teams approvals channel.
3. The card's **Review and approve** button opens the GitHub run. You need a GitHub account; the repository is public. Approve or reject there. The operator cannot approve their own request.
4. If you approve, the workflow re-checks that the change list is unchanged and applies it as `mi-nebo-rbac`. A second card reports the result.

You'll see roughly three requests per stage, listed in the plan. A request never contains Owner, User Access Administrator or Role Based Access Control Administrator: the workflow refuses those before they reach you.

## At the end

The operator destroys the stacks and asks the workflow to remove its role assignments, which you approve. Then you run `9-Remove-Nebo.ps1`. It removes any role assignments still left on the NEBo groups, then the lock, then deletes the five groups, typing each name to confirm. `-PurgeKeyVault` also frees the soft-deleted Key Vault name at once.
