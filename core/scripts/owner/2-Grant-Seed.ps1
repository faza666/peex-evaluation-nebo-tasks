#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.Resources, Az.ManagedServiceIdentity, Az.Storage

<#
.SYNOPSIS
Step 2 of 2 for the subscription owner: gives the two workflow identities their first rights and locks the
identity that applies role assignments. After this, every new role goes through your approval in GitHub.

.DESCRIPTION
Purpose
  From now on, every NEBo role assignment is code, applied by a GitHub workflow (rbac.yml) signed in as
  the managed identity mi-nebo-rbac. That workflow can only run after you approve it in GitHub; Teams tells
  you when a request is waiting. A workflow can't grant its own first rights, so this script makes the
  only hand-made grants to identities ("seed grants").

What it does
  1. Signs in with Connect-AzAccount and selects the subscription.
  2. Checks that the five NEBo resource groups exist (step 1). It also checks that the operator has created
     mi-nebo-rbac, mi-nebo-plan and the state storage account (stnebotf*) with its tfstate-rbac container.
  3. Makes the seed grants (built-in roles only):
       mi-nebo-rbac  Role Based Access Control Administrator  each NEBo resource group
       mi-nebo-rbac  Storage Blob Data Contributor            the tfstate-rbac container
       mi-nebo-plan  Reader                                   each NEBo resource group
       mi-nebo-plan  Storage Blob Data Reader                 the state storage account
     Role Based Access Control Administrator is the narrowest built-in role that can assign roles. It allows
     only creating and deleting role assignments, plus reading. It cannot create role definitions, so no
     custom role can be made through it. Contributor can't assign roles at all. The scope is the five
     NEBo resource groups, never the subscription.
  4. Puts a ReadOnly lock (nebo-approval-guard) on mi-nebo-rbac. The operator holds Contributor on
     rg-nebo-mgmt; without the lock they could add a federated credential to that identity and use it
     without your approval. The operator cannot remove the lock, because Contributor excludes
     Microsoft.Authorization writes and deletes. Signing in as the identity is not affected.

Methods
  Identities: Get-AzUserAssignedIdentity. Storage: Get-AzStorageAccount and Get-AzRmStorageContainer.
  These are management-plane calls; no data is read. Role assignments go through the ARM REST API
  (Invoke-AzRestMethod) with principalType 'ServicePrincipal', so nothing is looked up in Microsoft Entra ID.
  The lock uses New-AzResourceLock. The script is idempotent and honours -WhatIf.

.PARAMETER SubscriptionId
The NEBo subscription.

.PARAMETER TenantId
Optional. The tenant to sign in to, if your account can reach several.

.EXAMPLE
./2-Grant-Seed.ps1 -SubscriptionId <subscription-id> -WhatIf

.EXAMPLE
./2-Grant-Seed.ps1 -SubscriptionId <subscription-id>

.NOTES
Rights needed: Owner on the subscription. No Entra ID role.
Check the result at any time with Show-NeboAccess.ps1. Undo: 9-Remove-Nebo.ps1.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [guid] $SubscriptionId,
    [guid] $TenantId
)

. (Join-Path $PSScriptRoot 'NeboOwner.Common.ps1')

$sub = $SubscriptionId.ToString()
$tenant = if ($TenantId) { $TenantId.ToString() } else { $null }

Connect-NeboSubscription -SubscriptionId $sub -TenantId $tenant | Out-Null

# --- 2. Preconditions ----------------------------------------------------------------------------
$missing = @($NeboResourceGroups.Keys | Where-Object { -not (Get-AzResourceGroup -Name $_ -ErrorAction SilentlyContinue) })
if ($missing) { throw "Missing resource groups: $($missing -join ', '). Run 1-Prepare-Subscription.ps1 first." }

$identities = @{}
foreach ($name in $NeboRbacIdentity, $NeboPlanIdentity) {
    $identity = Get-AzUserAssignedIdentity -ResourceGroupName $NeboMgmtGroup -Name $name -ErrorAction SilentlyContinue
    if (-not $identity) { throw "$name not found in $NeboMgmtGroup. Ask the operator to create the identities first." }
    $identities[$name] = $identity
}

$accounts = @(Get-AzStorageAccount -ResourceGroupName $NeboMgmtGroup | Where-Object StorageAccountName -like "$NeboStateAccountPrefix*")
if ($accounts.Count -ne 1) {
    throw "Expected exactly one $NeboStateAccountPrefix* storage account in $NeboMgmtGroup, found $($accounts.Count). Ask the operator to create the state storage first."
}
$account = $accounts[0]
if ($account.AllowSharedKeyAccess -ne $false) {
    Write-Warning "$($account.StorageAccountName) still allows shared keys; the operator's bootstrap turns them off."
}
$container = Get-AzRmStorageContainer -ResourceGroupName $NeboMgmtGroup -StorageAccountName $account.StorageAccountName `
    -Name $NeboRbacStateContainer -ErrorAction SilentlyContinue
if (-not $container) { throw "Container $NeboRbacStateContainer not found in $($account.StorageAccountName)." }
$containerScope = "$($account.Id)/blobServices/default/containers/$NeboRbacStateContainer"

Write-Host "`nFound: $NeboRbacIdentity, $NeboPlanIdentity, $($account.StorageAccountName)/$NeboRbacStateContainer"

# --- 3. Seed grants ------------------------------------------------------------------------------
$rbac = $identities[$NeboRbacIdentity]
$plan = $identities[$NeboPlanIdentity]

Write-Host "`nSeed grants:"
foreach ($group in $NeboResourceGroups.Keys) {
    $scope = Get-NeboResourceGroupId -SubscriptionId $sub -Name $group
    Set-NeboRoleAssignment -SubscriptionId $sub -Scope $scope -PrincipalId $rbac.PrincipalId `
        -PrincipalType ServicePrincipal -RoleName 'Role Based Access Control Administrator' -PrincipalLabel $NeboRbacIdentity
    Set-NeboRoleAssignment -SubscriptionId $sub -Scope $scope -PrincipalId $plan.PrincipalId `
        -PrincipalType ServicePrincipal -RoleName 'Reader' -PrincipalLabel $NeboPlanIdentity
}
Set-NeboRoleAssignment -SubscriptionId $sub -Scope $containerScope -PrincipalId $rbac.PrincipalId `
    -PrincipalType ServicePrincipal -RoleName 'Storage Blob Data Contributor' -PrincipalLabel $NeboRbacIdentity
Set-NeboRoleAssignment -SubscriptionId $sub -Scope $account.Id -PrincipalId $plan.PrincipalId `
    -PrincipalType ServicePrincipal -RoleName 'Storage Blob Data Reader' -PrincipalLabel $NeboPlanIdentity

# --- 4. Lock the approval identity ---------------------------------------------------------------
Write-Host "`nLock:"
$lockTarget = @{
    ResourceGroupName = $NeboMgmtGroup
    ResourceName      = $NeboRbacIdentity
    ResourceType      = 'Microsoft.ManagedIdentity/userAssignedIdentities'
}
$lock = Get-AzResourceLock @lockTarget -ErrorAction SilentlyContinue | Where-Object Name -eq $NeboLockName
if ($lock) {
    Write-Host "  exists   ReadOnly lock $NeboLockName on $NeboRbacIdentity"
}
elseif ($PSCmdlet.ShouldProcess($NeboRbacIdentity, "Add ReadOnly lock $NeboLockName")) {
    New-AzResourceLock @lockTarget -LockName $NeboLockName -LockLevel ReadOnly -Force `
        -LockNotes 'NEBo: keeps the role-assignment identity from being changed without the subscription owner.' | Out-Null
    Write-Host "  added    ReadOnly lock $NeboLockName on $NeboRbacIdentity"
}

Write-Host @"

Done. From now on, every NEBo role assignment arrives as an approval request: a card in your Teams
approvals channel links to the GitHub run, where you can review the exact list of roles and approve or
reject it. Run Show-NeboAccess.ps1 at any time to see every NEBo role assignment.
"@
