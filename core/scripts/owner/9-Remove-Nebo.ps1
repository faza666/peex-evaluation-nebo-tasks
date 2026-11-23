#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.Resources, Az.ManagedServiceIdentity, Az.KeyVault

<#
.SYNOPSIS
End of the project: removes everything NEBo left in the subscription: role assignments, the lock and the
five resource groups with all they contain.

.DESCRIPTION
Purpose
  The final teardown. Run it after the operator's workflows have destroyed their stacks and removed their
  role assignments. It also works if they haven't, because it removes whatever is left.

What it does
  1. Signs in with Connect-AzAccount and selects the subscription.
  2. Lists what is left (the same view as Show-NeboAccess.ps1).
  3. Removes every role assignment made at or below the five NEBo resource groups: the seed grants, the
     operator's grants and the ones the workflow made. Inherited assignments, such as your own Owner
     role, are never touched.
  4. Removes the ReadOnly lock nebo-approval-guard from mi-nebo-rbac. Other locks are only reported,
     and a resource group that still has one won't delete.
  5. Deletes the resource groups, stages first and rg-nebo-mgmt last. That deletes the managed identities
     and the Terraform state with them. You type each group's name to confirm, unless -Force is given.
  6. With -PurgeKeyVault, it also purges the soft-deleted NEBo Key Vault (kv-nebo-*), so the name is
     free at once. Otherwise Azure purges it after 7 days.

Methods
  Role assignments are listed and deleted through the ARM REST API (Invoke-AzRestMethod), so nothing is
  looked up in Microsoft Entra ID. Get-AzResourceLock and Remove-AzResourceLock handle locks,
  Remove-AzResourceGroup deletes the groups, and Get-AzKeyVault -InRemovedState with
  Remove-AzKeyVault -InRemovedState purges the vault. The script honours -WhatIf, so you can see
  everything it would do first.

.PARAMETER SubscriptionId
The NEBo subscription.

.PARAMETER TenantId
Optional. The tenant to sign in to, if your account can reach several.

.PARAMETER Force
Skips the type-the-name confirmation for each resource group.

.PARAMETER PurgeKeyVault
Also purges the soft-deleted kv-nebo-* Key Vault.

.EXAMPLE
./9-Remove-Nebo.ps1 -SubscriptionId <subscription-id> -WhatIf

.EXAMPLE
./9-Remove-Nebo.ps1 -SubscriptionId <subscription-id> -PurgeKeyVault

.NOTES
Rights needed: Owner on the subscription. This cannot be undone: the resource groups and everything in
them are deleted.
#>
[CmdletBinding(SupportsShouldProcess)]  # the typed group name is the confirmation; -Confirm adds per-step prompts
param(
    [Parameter(Mandatory)] [guid] $SubscriptionId,
    [guid] $TenantId,
    [switch] $Force,
    [switch] $PurgeKeyVault
)

. (Join-Path $PSScriptRoot 'NeboOwner.Common.ps1')

$sub = $SubscriptionId.ToString()
$tenant = if ($TenantId) { $TenantId.ToString() } else { $null }

Connect-NeboSubscription -SubscriptionId $sub -TenantId $tenant | Out-Null

$existing = @($NeboResourceGroups.Keys | Where-Object { Get-AzResourceGroup -Name $_ -ErrorAction SilentlyContinue })
if (-not $existing) { Write-Host 'No NEBo resource groups left. Nothing to do.' }

# --- 3. Role assignments -------------------------------------------------------------------------
$names = Get-NeboIdentityNames
Write-Host "`nRole assignments:"
foreach ($group in $existing) {
    $scope = Get-NeboResourceGroupId -SubscriptionId $sub -Name $group
    foreach ($assignment in Get-NeboRoleAssignment -Scope $scope) {
        $p = $assignment.properties
        $who = if ($names.ContainsKey($p.principalId)) { $names[$p.principalId] } else { "$($p.principalType) $($p.principalId)" }
        $role = Get-AzRoleDefinition -Id (($p.roleDefinitionId -split '/')[-1]) -ErrorAction SilentlyContinue
        $roleName = if ($role) { $role.Name } else { $p.roleDefinitionId }
        Remove-NeboRoleAssignmentById -Id $assignment.id -Description "$roleName -> $who @ $(Format-NeboScope -Scope $p.scope)" -Confirm:$false
    }
}

# --- 4. Locks ------------------------------------------------------------------------------------
Write-Host "`nLocks:"
foreach ($group in $existing) {
    foreach ($lock in Get-AzResourceLock -ResourceGroupName $group -ErrorAction SilentlyContinue) {
        if ($lock.Name -eq $NeboLockName) {
            if ($PSCmdlet.ShouldProcess($lock.ResourceId, 'Remove lock')) {
                Remove-AzResourceLock -LockId $lock.LockId -Force | Out-Null
                Write-Host "  removed  $($lock.Name)"
            }
        }
        else {
            Write-Warning "Lock '$($lock.Name)' in $group was not made by NEBo and is left in place; that group won't delete until it is removed."
        }
    }
}

# --- 5. Resource groups --------------------------------------------------------------------------
Write-Host "`nResource groups:"
$order = 'rg-nebo-stage-c', 'rg-nebo-stage-b', 'rg-nebo-stage-a', 'rg-nebo-core', $NeboMgmtGroup
foreach ($group in $order | Where-Object { $_ -in $existing }) {
    $count = @(Get-AzResource -ResourceGroupName $group).Count
    if (-not $WhatIfPreference -and -not $Force) {
        $typed = Read-Host "Type '$group' to delete it and its $count resource(s), or press Enter to skip"
        if ($typed -ne $group) { Write-Host "  skipped  $group"; continue }
    }
    if ($PSCmdlet.ShouldProcess("$group ($count resources)", 'Delete resource group')) {
        Remove-AzResourceGroup -Name $group -Force | Out-Null
        Write-Host "  deleted  $group"
    }
}

# --- 6. Soft-deleted Key Vault -------------------------------------------------------------------
if ($PurgeKeyVault) {
    Write-Host "`nSoft-deleted Key Vaults:"
    foreach ($vault in Get-AzKeyVault -InRemovedState | Where-Object VaultName -like 'kv-nebo-*') {
        if ($PSCmdlet.ShouldProcess($vault.VaultName, 'Purge soft-deleted Key Vault')) {
            Remove-AzKeyVault -VaultName $vault.VaultName -Location $vault.Location -InRemovedState -Force
            Write-Host "  purged   $($vault.VaultName)"
        }
    }
}

Write-Host "`nDone. Run Show-NeboAccess.ps1 to confirm that nothing is left."
