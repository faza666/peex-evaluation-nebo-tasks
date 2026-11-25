# Shared by every stage, in rg-nebo-core. The subscription owner created the resource group; this stack only
# fills it, and terraform.yml applies it as mi-nebo-core. Role assignments on these resources live in
# core/rbac/grants.yaml as core/<tag> scopes, which find a resource by its nebo:scope tag.

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "core" {
  name = "rg-nebo-core"
}

locals {
  # Same suffix as core/scripts/ops/bootstrap-state.sh: the first 6 hex characters of sha256(subscription ID).
  suffix   = substr(sha256(data.azurerm_client_config.current.subscription_id), 0, 6)
  location = data.azurerm_resource_group.core.location
  tags     = { "nebo:stack" = "core" }

  # nebo:scope names the one resource a grant in core/rbac/grants.yaml means, e.g. core/acr.
  scoped = { for s in ["acr", "kv", "law", "amw", "acs"] : s => merge(local.tags, { "nebo:scope" = s }) }
}

# --- Logs and metrics -------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "core" {
  name                = "law-nebo-core"
  resource_group_name = data.azurerm_resource_group.core.name
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.5 # cost guard: ingestion stops for the day at 0.5 GB
  tags                = local.scoped.law
}

resource "azurerm_monitor_workspace" "core" {
  name                = "amw-nebo-core"
  resource_group_name = data.azurerm_resource_group.core.name
  location            = local.location
  tags                = local.scoped.amw
}

# --- Secrets ----------------------------------------------------------------------------------

# Container Apps on the consumption plan have no fixed outbound IP and are not a trusted Azure service, so a
# firewall that denies by default would lock them out. Access is by Azure RBAC only (no access policies), and
# only the identities named in core/rbac/grants.yaml get a data role.
# No prevent_destroy: the vault holds only secrets that can be set again, and the end of Stage C destroys it.
#trivy:ignore:AZU-0013
resource "azurerm_key_vault" "core" { # tflint-ignore: azurerm_resources_missing_prevent_destroy
  name                       = "kv-nebo-${local.suffix}"
  resource_group_name        = data.azurerm_resource_group.core.name
  location                   = local.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false # allows a clean teardown at the end of Stage C
  soft_delete_retention_days = 7
  tags                       = local.scoped.kv
}

# --- Container images -------------------------------------------------------------------------

# Permanent since the move to the corporate subscription (~$5 a month). Entra ID only: no admin user, and Basic
# has no anonymous pull. docker-build.yml pushes as mi-nebo-ci (AcrPush); the apps pull with their own identities.
resource "azurerm_container_registry" "core" {
  name                = "acrnebo${local.suffix}"
  resource_group_name = data.azurerm_resource_group.core.name
  location            = local.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.scoped.acr
}

# --- Alerts and budget ------------------------------------------------------------------------

# Azure Monitor alerts and budget warnings go to the notification address and, once the secret
# TEAMS_ALERTS_WEBHOOK_URL is set, to a Teams Workflows webhook that turns the common alert schema into a card.
resource "azurerm_monitor_action_group" "alerts" {
  name                = "ag-nebo-alerts"
  resource_group_name = data.azurerm_resource_group.core.name
  short_name          = "nebo"
  tags                = local.tags

  email_receiver {
    name                    = "operator"
    email_address           = var.notify_email
    use_common_alert_schema = true
  }

  dynamic "webhook_receiver" {
    # Only whether it is set decides the block; the URL itself stays sensitive.
    for_each = nonsensitive(var.alerts_webhook_url != "") ? ["teams"] : []
    content {
      name                    = webhook_receiver.value
      service_uri             = var.alerts_webhook_url
      use_common_alert_schema = true
    }
  }
}

# A budget on this resource group only: one on the subscription needs subscription-wide rights. Each stage
# stack sets one on its own group.
resource "azurerm_consumption_budget_resource_group" "core" {
  name              = "budget-nebo-core"
  resource_group_id = data.azurerm_resource_group.core.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  time_period {
    start_date = var.budget_start_date
  }

  dynamic "notification" {
    for_each = [50, 80, 100]
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThanOrEqualTo"
      threshold_type = "Actual"
      contact_groups = [azurerm_monitor_action_group.alerts.id]
    }
  }
}

# --- Email for pipeline notifications ---------------------------------------------------------

resource "azurerm_email_communication_service" "core" {
  name                = "ecs-nebo-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.core.name
  data_location       = "Europe"
  tags                = local.tags
}

resource "azurerm_email_communication_service_domain" "azure_managed" {
  name              = "AzureManagedDomain"
  email_service_id  = azurerm_email_communication_service.core.id
  domain_management = "AzureManaged"
  tags              = local.tags
}

# mi-nebo-notify sends through this resource with Entra sign-in (grant core/acs).
resource "azurerm_communication_service" "core" {
  name                = "acs-nebo-${local.suffix}"
  resource_group_name = data.azurerm_resource_group.core.name
  data_location       = "Europe"
  tags                = local.scoped.acs
}

resource "azurerm_communication_service_email_domain_association" "core" {
  communication_service_id = azurerm_communication_service.core.id
  email_service_domain_id  = azurerm_email_communication_service_domain.azure_managed.id
}
