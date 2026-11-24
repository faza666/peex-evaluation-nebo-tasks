# Shared helpers for the NEBo owner scripts. The scripts dot-source this file; don't run it on its own.
#
# Every Azure call here goes to Azure Resource Manager only. Nothing reads or writes Microsoft Entra ID:
#   - role assignments are made through the ARM REST API (Invoke-AzRestMethod) with an explicit
#     principalType, so Azure never has to look the principal up in the directory;
#   - managed identities are found with Get-AzUserAssignedIdentity, which is an ARM call too.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The five NEBo resource groups and the stage each one belongs to (stored in the nebo:rg tag).
$NeboResourceGroups = [ordered]@{
    'rg-nebo-mgmt'    = 'mgmt'      # Terraform state and every managed identity; lives A -> end of C
    'rg-nebo-core'    = 'core'      # shared services (registry, Key Vault, logs, email); A -> end of C
    'rg-nebo-stage-a' = 'stage-a'   # Container Apps and the VM; A -> end of B
    'rg-nebo-stage-b' = 'stage-b'   # AKS; B -> end of C
    'rg-nebo-stage-c' = 'stage-c'   # App Gateway; C only
}
$NeboMgmtGroup = 'rg-nebo-mgmt'
$NeboRbacIdentity = 'mi-nebo-rbac'       # applies role assignments, only after you approve them
$NeboPlanIdentity = 'mi-nebo-plan'       # read-only: computes what a change would do
$NeboRbacStateContainer = 'tfstate-rbac' # Terraform state of the role assignments
$NeboStateAccountPrefix = 'stnebotf'
$NeboLockName = 'nebo-approval-guard'
$RoleAssignmentApiVersion = '2022-04-01'
$RoleDefinitionApiVersion = '2022-04-01'
$NeboRoleIds = @{}   # role name -> GUID, filled by Get-NeboRoleId
$NeboRoleNames = @{} # role GUID -> name, filled by Get-NeboRoleName

function Connect-NeboSubscription {
    <#
    .SYNOPSIS
    Signs in to Azure (Connect-AzAccount, the Az-module equivalent of `az login`) and selects the subscription.
    Stops if the active context doesn't end up on exactly that subscription.
    #>
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId,
        [string] $TenantId
    )
    $context = Get-AzContext
    if (-not $context -or -not $context.Subscription -or $context.Subscription.Id -ne $SubscriptionId) {
        $connect = @{ Subscription = $SubscriptionId }
        if ($TenantId) { $connect.Tenant = $TenantId }
        Write-Host 'Signing in to Azure (Connect-AzAccount) ...'
        Connect-AzAccount @connect -WhatIf:$false | Out-Null
    }
    $context = Set-AzContext -Subscription $SubscriptionId -WhatIf:$false
    if ($context.Subscription.Id -ne $SubscriptionId) {
        throw "The active subscription is $($context.Subscription.Id), not $SubscriptionId. Nothing was changed."
    }
    Write-Host "Subscription: $($context.Subscription.Name) ($SubscriptionId), signed in as $($context.Account.Id)"
    return $context
}

function Get-NeboResourceGroupId {
    param([Parameter(Mandatory)] [string] $SubscriptionId, [Parameter(Mandatory)] [string] $Name)
    "/subscriptions/$SubscriptionId/resourceGroups/$Name"
}

function Get-NeboRoleId {
    <#
    .SYNOPSIS
    Returns the GUID of a built-in role, looked up by its exact name through the ARM REST API.
    Cached per run. Get-AzRoleDefinition isn't used: it prints a breaking-change warning on every call.
    #>
    param([Parameter(Mandatory)] [string] $SubscriptionId, [Parameter(Mandatory)] [string] $RoleName)
    if ($NeboRoleIds.ContainsKey($RoleName)) { return $NeboRoleIds[$RoleName] }
    $filter = [uri]::EscapeDataString("roleName eq '$RoleName'")
    $path = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions?`$filter=$filter&api-version=$RoleDefinitionApiVersion"
    $response = Invoke-AzRestMethod -Method GET -Path $path -WhatIf:$false
    if ($response.StatusCode -ne 200) {
        throw "Looking up role '$RoleName' failed ($($response.StatusCode)): $($response.Content)"
    }
    $roles = @(($response.Content | ConvertFrom-Json).value)
    if (-not $roles) { throw "Role '$RoleName' was not found." }
    $builtIn = @($roles | Where-Object { $_.properties.type -eq 'BuiltInRole' })
    if ($builtIn.Count -ne 1) { throw "'$RoleName' is not a built-in role; NEBo uses built-in roles only." }
    $NeboRoleIds[$RoleName] = $builtIn[0].name
    return $builtIn[0].name
}

function Get-NeboRoleName {
    <# .SYNOPSIS Returns a role's name from its GUID through the ARM REST API, or the GUID if it can't be read. Cached per run. #>
    param([Parameter(Mandatory)] [string] $SubscriptionId, [Parameter(Mandatory)] [string] $RoleId)
    if (-not $NeboRoleNames.ContainsKey($RoleId)) {
        $path = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/$($RoleId)?api-version=$RoleDefinitionApiVersion"
        $response = Invoke-AzRestMethod -Method GET -Path $path -WhatIf:$false
        $NeboRoleNames[$RoleId] = if ($response.StatusCode -eq 200) { ($response.Content | ConvertFrom-Json).properties.roleName } else { $RoleId }
    }
    return $NeboRoleNames[$RoleId]
}

function New-NeboDeterministicGuid {
    <# .SYNOPSIS A GUID derived from a text, so re-running a script reuses the same role assignment name. #>
    param([Parameter(Mandatory)] [string] $Text)
    $hash = [System.Security.Cryptography.MD5]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text))
    return [guid]::new($hash).ToString()
}

function Get-NeboRoleAssignment {
    <#
    .SYNOPSIS
    Lists the role assignments made at the given scope or below it (not the ones inherited from above),
    through the ARM REST API. A scope that doesn't exist yet returns nothing.
    #>
    param([Parameter(Mandatory)] [string] $Scope)
    $results = [System.Collections.Generic.List[object]]::new()
    $path = "$Scope/providers/Microsoft.Authorization/roleAssignments?api-version=$RoleAssignmentApiVersion"
    while ($path) {
        $response = Invoke-AzRestMethod -Method GET -Path $path -WhatIf:$false
        if ($response.StatusCode -eq 404) { return $results }
        if ($response.StatusCode -ne 200) {
            throw "Listing role assignments at $Scope failed ($($response.StatusCode)): $($response.Content)"
        }
        $page = $response.Content | ConvertFrom-Json
        foreach ($assignment in $page.value) {
            if ($assignment.properties.scope.StartsWith($Scope, [System.StringComparison]::OrdinalIgnoreCase)) {
                $results.Add($assignment)
            }
        }
        $next = $page.PSObject.Properties['nextLink']
        $path = if ($next -and $next.Value) { ([uri]$next.Value).PathAndQuery } else { $null }
    }
    return $results
}

function Set-NeboRoleAssignment {
    <#
    .SYNOPSIS
    Assigns a built-in role to a principal at a scope, unless that exact assignment already exists.
    .DESCRIPTION
    Uses PUT on Microsoft.Authorization/roleAssignments through Invoke-AzRestMethod, with an explicit
    principalType ('User' or 'ServicePrincipal'; managed identities are service principals). Because the
    type is given, Azure does not look the principal up in Microsoft Entra ID. The assignment name is a GUID
    derived from scope, principal and role, so a re-run never creates a duplicate. Honours -WhatIf.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $SubscriptionId,
        [Parameter(Mandatory)] [string] $Scope,
        [Parameter(Mandatory)] [string] $PrincipalId,
        [Parameter(Mandatory)] [ValidateSet('User', 'ServicePrincipal')] [string] $PrincipalType,
        [Parameter(Mandatory)] [string] $RoleName,
        [Parameter(Mandatory)] [string] $PrincipalLabel
    )
    $roleId = Get-NeboRoleId -SubscriptionId $SubscriptionId -RoleName $RoleName
    $existing = Get-NeboRoleAssignment -Scope $Scope | Where-Object {
        $_.properties.principalId -eq $PrincipalId -and
        $_.properties.roleDefinitionId -like "*/$roleId" -and
        $_.properties.scope -eq $Scope
    }
    $shortScope = Format-NeboScope -Scope $Scope
    if ($existing) {
        Write-Host "  exists   $RoleName -> $PrincipalLabel @ $shortScope"
        return
    }
    if ($PSCmdlet.ShouldProcess("$PrincipalLabel @ $shortScope", "Assign role '$RoleName'")) {
        $name = New-NeboDeterministicGuid -Text "$Scope|$PrincipalId|$roleId".ToLowerInvariant()
        $body = @{
            properties = @{
                roleDefinitionId = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/$roleId"
                principalId      = $PrincipalId
                principalType    = $PrincipalType
                description      = 'NEBo seed grant (core/scripts/owner)'
            }
        } | ConvertTo-Json -Depth 5
        $path = "$Scope/providers/Microsoft.Authorization/roleAssignments/$($name)?api-version=$RoleAssignmentApiVersion"
        $response = Invoke-AzRestMethod -Method PUT -Path $path -Payload $body -Confirm:$false
        if ($response.StatusCode -notin 200, 201) {
            throw "Assigning '$RoleName' to $PrincipalLabel at $shortScope failed ($($response.StatusCode)): $($response.Content)"
        }
        Write-Host "  assigned $RoleName -> $PrincipalLabel @ $shortScope"
    }
}

function Remove-NeboRoleAssignmentById {
    <# .SYNOPSIS Deletes one role assignment by its full resource ID (ARM REST API). Honours -WhatIf. #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Id, [Parameter(Mandatory)] [string] $Description)
    if ($PSCmdlet.ShouldProcess($Description, 'Remove role assignment')) {
        $response = Invoke-AzRestMethod -Method DELETE -Path "$($Id)?api-version=$RoleAssignmentApiVersion" -Confirm:$false
        if ($response.StatusCode -notin 200, 204) {
            throw "Removing $Description failed ($($response.StatusCode)): $($response.Content)"
        }
        Write-Host "  removed  $Description"
    }
}

function Format-NeboScope {
    <# .SYNOPSIS Shortens a scope ID for display: the resource group, plus the resource below it if any. #>
    param([Parameter(Mandatory)] [string] $Scope)
    if ($Scope -match '/resourceGroups/([^/]+)(/providers/(.+))?$') {
        if ($Matches[3]) { return "$($Matches[1])/$($Matches[3])" }
        return $Matches[1]
    }
    return $Scope
}

function Get-NeboIdentityNames {
    <# .SYNOPSIS Maps principal IDs to names for every managed identity in rg-nebo-mgmt. #>
    $map = @{}
    $group = Get-AzResourceGroup -Name $NeboMgmtGroup -ErrorAction SilentlyContinue
    if ($group) {
        foreach ($identity in Get-AzUserAssignedIdentity -ResourceGroupName $NeboMgmtGroup) {
            $map[$identity.PrincipalId] = $identity.Name
        }
    }
    return $map
}
