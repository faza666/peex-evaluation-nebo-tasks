# Scripts for the Subscription Owner

NEBo is a learning project deployed from this public repository by GitHub Actions. The operator has no Owner rights, and nothing is created in Microsoft Entra ID. You run two scripts once; after that, every role assignment waits for your approval.

| When | Script | What it does |
|---|---|---|
| 1. Now | [`1-Prepare-Subscription.ps1`](1-Prepare-Subscription.ps1) | Creates five resource groups `rg-nebo-*`. Gives the operator Contributor and Storage Blob Data Contributor on `rg-nebo-mgmt` only. |
| 2. When the operator asks | [`2-Grant-Seed.ps1`](2-Grant-Seed.ps1) | In those groups, gives `mi-nebo-rbac` the right to assign roles (RBAC Administrator) and `mi-nebo-plan` read-only access (Reader). Locks `mi-nebo-rbac`. |
| Any time | [`Show-NeboAccess.ps1`](Show-NeboAccess.ps1) | Lists NEBo's groups, role assignments and locks. Changes nothing. |
| At the end | [`9-Remove-Nebo.ps1`](9-Remove-Nebo.ps1) | Removes everything NEBo created. |

**Running them.** PowerShell 7.2+ with the Az modules (Azure Cloud Shell has both), signed in as subscription Owner. The operator sends you the exact commands. Each script signs in, checks the subscription and is safe to re-run. Add `-WhatIf` to preview the changes; `Get-Help ./<script>.ps1 -Full` explains every step.

**Approvals.** A card arrives in your Teams chat with the operator → **Review and approve** → on GitHub, **Review deployments** → **Approve** or **Reject**. Nothing is assigned before that. Only built-in roles, only on the NEBo resource groups; Owner, User Access Administrator and RBAC Administrator are never requested.
