#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.Resources, Az.ManagedServiceIdentity

<#
.SYNOPSIS
Read-only audit: lists the NEBo resource groups, every role assignment made on them, and the locks.
Changes nothing; run it whenever you want to see what NEBo can do in your subscription.

.DESCRIPTION
Purpose
  Every NEBo role assignment should be either one of the seed grants from 2-Grant-Seed.ps1 or one you
  approved in GitHub. This script shows the full picture so you can check that.

What it shows
  1. The five NEBo resource groups: whether they exist, their region and how many resources each holds.
  2. Every role assignment made at a NEBo resource group or on a resource inside one. Assignments
     inherited from the subscription (for example your own Owner role) are left out. For each:
     the scope, the role name, the principal and its type, and the description.
     Managed identities in rg-nebo-mgmt are shown by name. Other principals show their object ID, with the
     operator labelled if you pass -OperatorObjectId.
  3. The management locks in the NEBo resource groups.

Methods
  Get-AzResourceGroup, Get-AzResource, Get-AzResourceLock and Get-AzUserAssignedIdentity; role assignments
  are read with GET on Microsoft.Authorization/roleAssignments through the ARM REST API
  (Invoke-AzRestMethod). Nothing is looked up in Microsoft Entra ID, so you need no Entra permissions.

.PARAMETER SubscriptionId
The NEBo subscription.

.PARAMETER OperatorObjectId
Optional. The operator's object ID, so their assignments are labelled "operator".

.PARAMETER TenantId
Optional. The tenant to sign in to, if your account can reach several.

.EXAMPLE
./Show-NeboAccess.ps1 -SubscriptionId <subscription-id> -OperatorObjectId <object-id>

.NOTES
Rights needed: Reader on the subscription is enough.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [guid] $SubscriptionId,
    [guid] $OperatorObjectId,
    [guid] $TenantId
)

. (Join-Path $PSScriptRoot 'NeboOwner.Common.ps1')

$sub = $SubscriptionId.ToString()
$tenant = if ($TenantId) { $TenantId.ToString() } else { $null }
$operator = if ($OperatorObjectId) { $OperatorObjectId.ToString() } else { $null }

Connect-NeboSubscription -SubscriptionId $sub -TenantId $tenant | Out-Null

# --- 1. Resource groups --------------------------------------------------------------------------
$groups = foreach ($name in $NeboResourceGroups.Keys) {
    $group = Get-AzResourceGroup -Name $name -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ResourceGroup = $name
        Exists        = [bool]$group
        Location      = if ($group) { $group.Location } else { '' }
        Resources     = if ($group) { @(Get-AzResource -ResourceGroupName $name).Count } else { 0 }
    }
}
Write-Host "`nResource groups"
$groups | Format-Table -AutoSize | Out-Host

# --- 2. Role assignments -------------------------------------------------------------------------
$names = Get-NeboIdentityNames
$roleNames = @{}
$assignments = foreach ($group in $groups | Where-Object Exists) {
    $scope = Get-NeboResourceGroupId -SubscriptionId $sub -Name $group.ResourceGroup
    foreach ($assignment in Get-NeboRoleAssignment -Scope $scope) {
        $p = $assignment.properties
        $roleId = ($p.roleDefinitionId -split '/')[-1]
        if (-not $roleNames.ContainsKey($roleId)) {
            $definition = Get-AzRoleDefinition -Id $roleId -ErrorAction SilentlyContinue
            $roleNames[$roleId] = if ($definition) { $definition.Name } else { $roleId }
        }
        $principal = if ($names.ContainsKey($p.principalId)) { $names[$p.principalId] }
        elseif ($operator -and $p.principalId -eq $operator) { "operator ($($p.principalId))" }
        else { $p.principalId }
        $description = $p.PSObject.Properties['description']
        [pscustomobject]@{
            Scope       = Format-NeboScope -Scope $p.scope
            Role        = $roleNames[$roleId]
            Principal   = $principal
            Type        = $p.principalType
            Description = if ($description -and $description.Value) { $description.Value } else { '' }
        }
    }
}
Write-Host "Role assignments made on NEBo scopes ($(@($assignments).Count))"
$assignments | Sort-Object Scope, Principal, Role | Format-Table -AutoSize -Wrap | Out-Host

# --- 3. Locks ------------------------------------------------------------------------------------
$locks = foreach ($group in $groups | Where-Object Exists) {
    foreach ($lock in Get-AzResourceLock -ResourceGroupName $group.ResourceGroup -ErrorAction SilentlyContinue) {
        [pscustomobject]@{
            Name  = $lock.Name
            Level = $lock.Properties.level
            On    = Format-NeboScope -Scope ($lock.ResourceId -replace '/providers/Microsoft.Authorization/locks/[^/]+$', '')
        }
    }
}
Write-Host 'Locks'
if ($locks) { $locks | Format-Table -AutoSize | Out-Host } else { Write-Host "  none`n" }
