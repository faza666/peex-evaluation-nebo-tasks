# The identity GitHub Actions signs in as, through OIDC: no secret is stored in GitHub.

resource "azurerm_user_assigned_identity" "github" {
  name                = "id-nebo-github"
  resource_group_name = azurerm_resource_group.core.name
  location            = var.location
  tags                = local.tags
}

locals {
  # GitHub's OIDC subject names the owner and the repository with their immutable IDs:
  #   repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>
  github_repo_subject = format("repo:%s@%d/%s@%d", split("/", var.github_repo)[0], var.github_owner_id,
  split("/", var.github_repo)[1], var.github_repo_id)

  # Which workflow runs may use the identity: the two deployment environments, the main
  # branch (scheduled and manual runs) and pull requests.
  github_subjects = {
    env-dev      = "${local.github_repo_subject}:environment:dev"
    env-prod     = "${local.github_repo_subject}:environment:prod"
    branch-main  = "${local.github_repo_subject}:ref:refs/heads/main"
    pull-request = "${local.github_repo_subject}:pull_request"
  }
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.github_subjects

  name                      = "github-${each.key}"
  user_assigned_identity_id = azurerm_user_assigned_identity.github.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = each.value
}

# --- What the GitHub identity may do ----------------------------------------------------------
# Read everything (status and sleep-guard queries), manage only the core resource group here;
# each later stack grants Contributor on its own resource group. AcrPush comes with the registry in A1.

resource "azurerm_role_assignment" "github_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "github_core_contributor" {
  scope                = azurerm_resource_group.core.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "github_kv_secrets_user" {
  scope                = azurerm_key_vault.core.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.github.principal_id
  principal_type       = "ServicePrincipal"
}

# --- What you may do in the data plane --------------------------------------------------------

resource "azurerm_role_assignment" "me_kv_secrets_officer" {
  scope                = azurerm_key_vault.core.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
