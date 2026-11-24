#Requires -Version 7.2
#Requires -Modules Az.Accounts, Az.Resources

<#
.SYNOPSIS
Step 1 of 2 for the subscription owner: creates the five NEBo resource groups and gives the NEBo operator
the rights to set up Terraform state and managed identities in rg-nebo-mgmt.

.DESCRIPTION
Purpose
  NEBo is a learning project whose Azure resources are deployed from a public GitHub repository through
  managed identities. The operator gets no subscription-wide rights. This script prepares the
  only things that need the subscription owner up front.

What it does
  1. Signs in with Connect-AzAccount (the Az-module equivalent of `az login`) and selects the
     subscription. It stops if the context doesn't match -SubscriptionId.
  2. Creates the resource groups with New-AzResourceGroup, tagged nebo:rg=<stage>:
       rg-nebo-mgmt     Terraform state and every managed identity   (lives until the end of the project)
       rg-nebo-core     shared services                               (until the end)
       rg-nebo-stage-a  Container Apps and a VM                       (stages A and B)
       rg-nebo-stage-b  AKS                                           (stages B and C)
       rg-nebo-stage-c  App Gateway                                   (stage C)
     Empty resource groups cost nothing. Existing groups are reported and left as they are.
  3. Grants the operator two built-in roles, both on rg-nebo-mgmt only:
       Contributor                    to create the state storage account and the managed identities
       Storage Blob Data Contributor  to read and write the Terraform state blobs; Contributor alone
                                      cannot, because the account accepts sign-in tokens only (no keys)

Methods
  Role assignments are made through the Azure Resource Manager REST API (Invoke-AzRestMethod, PUT on
  Microsoft.Authorization/roleAssignments) with principalType 'User'. Because the type is given, nothing
  is looked up in Microsoft Entra ID, and you need no Entra permissions. The assignment names are derived
  from scope, principal and role, so running the script again changes nothing. Role IDs are looked up by
  name through the same API. Only built-in roles are used; no custom roles are created.

What comes next
  The operator creates the state storage account and the managed identities in rg-nebo-mgmt, then asks
  you to run 2-Grant-Seed.ps1.

.PARAMETER SubscriptionId
The subscription to prepare.

.PARAMETER OperatorObjectId
The operator's object ID. They read it themselves with `az ad signed-in-user show --query id -o tsv`
and send it to you.

.PARAMETER TenantId
Optional. The tenant to sign in to, if your account can reach several.

.PARAMETER Location
Azure region for the resource groups. Default: swedencentral.

.EXAMPLE
./1-Prepare-Subscription.ps1 -SubscriptionId <subscription-id> -OperatorObjectId <object-id> -WhatIf
Shows every change without making it.

.EXAMPLE
./1-Prepare-Subscription.ps1 -SubscriptionId <subscription-id> -OperatorObjectId <object-id>

.NOTES
Rights needed: Owner (or User Access Administrator plus Contributor) on the subscription. No Entra ID role.
Undo: 9-Remove-Nebo.ps1 removes everything NEBo created, or delete the two role assignments and the empty
resource groups in the portal.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [guid] $SubscriptionId,
    [Parameter(Mandatory)] [guid] $OperatorObjectId,
    [guid] $TenantId,
    [string] $Location = 'swedencentral'
)

. (Join-Path $PSScriptRoot 'NeboOwner.Common.ps1')

$sub = $SubscriptionId.ToString()
$tenant = if ($TenantId) { $TenantId.ToString() } else { $null }
$operator = $OperatorObjectId.ToString()

Connect-NeboSubscription -SubscriptionId $sub -TenantId $tenant | Out-Null

Write-Host "`nResource groups ($Location):"
foreach ($name in $NeboResourceGroups.Keys) {
    $group = Get-AzResourceGroup -Name $name -ErrorAction SilentlyContinue
    if ($group) {
        Write-Host "  exists   $name ($($group.Location))"
        if ($group.Location -ne $Location) {
            Write-Warning "$name is in $($group.Location), not $Location. Left as it is."
        }
        continue
    }
    if ($PSCmdlet.ShouldProcess($name, "Create resource group in $Location")) {
        New-AzResourceGroup -Name $name -Location $Location -Tag @{ 'nebo:rg' = $NeboResourceGroups[$name] } | Out-Null
        Write-Host "  created  $name"
    }
}

Write-Host "`nOperator rights on ${NeboMgmtGroup}:"
$mgmtScope = Get-NeboResourceGroupId -SubscriptionId $sub -Name $NeboMgmtGroup
foreach ($role in 'Contributor', 'Storage Blob Data Contributor') {
    Set-NeboRoleAssignment -SubscriptionId $sub -Scope $mgmtScope -PrincipalId $operator `
        -PrincipalType User -RoleName $role -PrincipalLabel "operator ($operator)"
}

Write-Host @"

Done. Tell the operator that step 1 is complete. They now create the Terraform state storage and the
managed identities in $NeboMgmtGroup, and then ask you to run 2-Grant-Seed.ps1.
"@
