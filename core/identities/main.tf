# Every managed identity NEBo uses, with its GitHub (and later Kubernetes) federated credentials.
# The list is identities.yaml; this file only turns it into resources. No role assignments here: those are
# in core/rbac and need the subscription owner's approval.

data "azurerm_resource_group" "mgmt" {
  name = "rg-nebo-mgmt"
}

locals {
  config = yamldecode(file("${path.module}/identities.yaml"))

  # GitHub's OIDC subject names the owner and the repository with their immutable IDs:
  #   repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>
  github_subject_prefix = format("repo:%s@%d/%s@%d", split("/", var.github_repo)[0], var.github_owner_id,
  split("/", var.github_repo)[1], var.github_repo_id)

  # name => { group, purpose, github, kubernetes } for every identity in an active group.
  identities = merge([
    for group, g in local.config.groups : {
      for name, i in g.identities : name => {
        group      = group
        purpose    = i.purpose
        github     = try(i.github, [])
        kubernetes = try(i.kubernetes, [])
      }
    } if g.active
  ]...)

  # "<identity>/<context>" => credential, e.g. "mi-nebo-rbac/environment:rbac".
  github_credentials = merge([
    for name, i in local.identities : {
      for context in i.github : "${name}/${context}" => {
        identity = name
        name     = "github-${replace(replace(context, ":", "-"), "/", "-")}"
        subject  = "${local.github_subject_prefix}:${context}"
      }
    }
  ]...)

  # "<identity>/<namespace>:<service account>" => credential; empty until the AKS issuer is known.
  kubernetes_credentials = var.aks_oidc_issuer == null ? {} : merge([
    for name, i in local.identities : {
      for account in i.kubernetes : "${name}/${account}" => {
        identity = name
        name     = "aks-${replace(account, ":", "-")}"
        subject  = "system:serviceaccount:${account}"
      }
    }
  ]...)
}

resource "azurerm_user_assigned_identity" "this" {
  for_each = local.identities

  name                = each.key
  resource_group_name = data.azurerm_resource_group.mgmt.name
  location            = data.azurerm_resource_group.mgmt.location
  tags = {
    "nebo:stack" = "identities"
    "nebo:group" = each.value.group
  }
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.github_credentials

  name                      = each.value.name
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.value.identity].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = each.value.subject
}

resource "azurerm_federated_identity_credential" "kubernetes" {
  for_each = local.kubernetes_credentials

  name                      = each.value.name
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.value.identity].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.aks_oidc_issuer
  subject                   = each.value.subject
}
