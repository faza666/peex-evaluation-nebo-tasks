# Every NEBo role assignment. The list is grants.yaml; this file only checks it and resolves its names to IDs.
# rbac.yml applies it as mi-nebo-rbac, and only after the subscription owner approves the run in GitHub.

locals {
  config = yamldecode(file("${path.module}/grants.yaml"))

  groups = ["mgmt", "core", "stage-a", "stage-b", "stage-c"]

  # An unset secret reaches Terraform as an empty string. Whether it is set is not secret, so error
  # messages can use it.
  operator_id  = var.operator_object_id == "" ? null : var.operator_object_id
  operator_set = nonsensitive(local.operator_id != null)

  # Roles that can hand out further rights. Refused here, and again by core/scripts/ci/rbac-changes.sh.
  forbidden_roles = ["owner", "user access administrator", "role based access control administrator"]

  # A grant is "<role> @ <scope>"; see the scope keys at the top of grants.yaml.
  line_pattern = "^\\s*(\\S.*?)\\s*@\\s*(\\S+)\\s*$"
  scope_patterns = [
    "^rg:(${join("|", local.groups)})$",
    "^container:tfstate-(core|stage-a|stage-b|stage-c)$", # never the identities or rbac state
    "^mi:mi-nebo-[a-z0-9-]+$",
    "^(${join("|", local.groups)})/[a-z0-9-]+$",
  ]

  # Every grant line of an active group, before checks.
  lines = flatten([
    for group, g in local.config.groups : [
      for principal, grants in g.grants : [
        for line in grants : { group = group, principal = principal, line = line }
      ]
    ] if g.active
  ])

  # "<principal> | <role> | <scope>" => grant. The key is also the resource address, so plans read as names.
  grouped = {
    for l in local.lines : "${l.principal} | ${regex(local.line_pattern, l.line)[0]} | ${regex(local.line_pattern, l.line)[1]}" => {
      group     = l.group
      principal = l.principal
      role      = regex(local.line_pattern, l.line)[0]
      scope     = regex(local.line_pattern, l.line)[1]
    }... if can(regex(local.line_pattern, l.line))
  }
  grants = { for k, list in local.grouped : k => list[0] }

  problems = concat(
    [for l in local.lines : "\"${l.line}\" (${l.principal}) is not \"<role> @ <scope>\"" if !can(regex(local.line_pattern, l.line))],
    [for k, g in local.grants : "${k}: ${g.role} is never granted here" if contains(local.forbidden_roles, lower(g.role))],
    [for k, g in local.grants : "${k}: unknown principal" if g.principal != "operator" && !can(regex("^mi-nebo-[a-z0-9-]+$", g.principal))],
    [for k, g in local.grants : "${k}: unknown or refused scope" if alltrue([for p in local.scope_patterns : !can(regex(p, g.scope))])],
    [for k, g in local.grants : "${k}: nothing may be granted on mi-nebo-rbac" if g.scope == "mi:mi-nebo-rbac"],
    [for k, g in local.grants : "${k}: operator_object_id is not set" if g.principal == "operator" && !local.operator_set],
    [for k, list in local.grouped : "${k} is listed ${length(list)} times" if length(list) > 1],
  )

  identity_names = toset(concat(
    [for g in values(local.grants) : g.principal if g.principal != "operator"],
    [for g in values(local.grants) : trimprefix(g.scope, "mi:") if startswith(g.scope, "mi:")],
  ))
  containers    = toset([for g in values(local.grants) : trimprefix(g.scope, "container:") if startswith(g.scope, "container:")])
  resource_keys = toset([for g in values(local.grants) : g.scope if can(regex(local.scope_patterns[3], g.scope))])

  subscription = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  # The account core/scripts/ops/bootstrap-state.sh creates: stnebotf + the first 6 hex characters of
  # sha256(subscription ID).
  state_account_id = format("%s/resourceGroups/rg-nebo-mgmt/providers/Microsoft.Storage/storageAccounts/stnebotf%s",
  local.subscription, substr(sha256(data.azurerm_client_config.current.subscription_id), 0, 6))
}

data "azurerm_client_config" "current" {
  lifecycle {
    precondition {
      condition     = length(local.problems) == 0
      error_message = "grants.yaml: ${join("; ", local.problems)}."
    }
  }
}

# Principals, and identities used as scopes (Managed Identity Operator). All live in rg-nebo-mgmt.
data "azurerm_user_assigned_identity" "this" {
  for_each = local.identity_names

  name                = each.key
  resource_group_name = "rg-nebo-mgmt"
}

# Read only to fail the plan if a container doesn't exist; the scope ID is built below.
data "azurerm_storage_container" "this" {
  for_each = local.containers

  name               = each.key
  storage_account_id = local.state_account_id
}

# "<group>/<tag>": the one resource in rg-nebo-<group> that its stack tagged nebo:scope=<tag>.
data "azurerm_resources" "this" {
  for_each = local.resource_keys

  resource_group_name = "rg-nebo-${split("/", each.key)[0]}"
  required_tags       = { "nebo:scope" = split("/", each.key)[1] }

  lifecycle {
    postcondition {
      condition     = length(self.resources) == 1
      error_message = "${each.key}: expected one resource tagged nebo:scope=${split("/", each.key)[1]} in rg-nebo-${split("/", each.key)[0]}."
    }
  }
}

resource "azurerm_role_assignment" "this" {
  for_each = local.grants

  scope = (
    startswith(each.value.scope, "rg:") ? "${local.subscription}/resourceGroups/rg-nebo-${trimprefix(each.value.scope, "rg:")}" :
    startswith(each.value.scope, "mi:") ? data.azurerm_user_assigned_identity.this[trimprefix(each.value.scope, "mi:")].id :
    startswith(each.value.scope, "container:") ? "${local.state_account_id}/blobServices/default/containers/${data.azurerm_storage_container.this[trimprefix(each.value.scope, "container:")].name}" :
    data.azurerm_resources.this[each.value.scope].resources[0].id
  )
  role_definition_name = each.value.role

  # With principal_type set, Azure doesn't look the principal up in Entra ID.
  principal_id   = each.value.principal == "operator" ? local.operator_id : data.azurerm_user_assigned_identity.this[each.value.principal].principal_id
  principal_type = each.value.principal == "operator" ? "User" : "ServicePrincipal"
  description    = "NEBo core/rbac/grants.yaml, group ${each.value.group}"
}
