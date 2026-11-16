data "azurerm_subscription" "current" {}
data "azurerm_client_config" "current" {}

locals {
  # Same suffix as scripts/ops/bootstrap-state.sh: the first 6 hex characters of sha256(subscription ID).
  suffix = substr(sha256(data.azurerm_subscription.current.subscription_id), 0, 6)
  tags   = { "nebo:stack" = "core" }
}

resource "azurerm_resource_group" "core" {
  name     = "rg-nebo-core"
  location = var.location
  tags     = local.tags
}

# --- Logs and metrics -------------------------------------------------------------------------

resource "azurerm_log_analytics_workspace" "core" {
  name                = "law-nebo-core"
  resource_group_name = azurerm_resource_group.core.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 0.5 # cost guard: ingestion stops for the day at 0.5 GB
  tags                = local.tags
}

resource "azurerm_monitor_workspace" "core" {
  name                = "amw-nebo-core"
  resource_group_name = azurerm_resource_group.core.name
  location            = var.location
  tags                = local.tags
}

# --- Secrets ----------------------------------------------------------------------------------

resource "azurerm_key_vault" "core" {
  name                       = "kv-nebo-${local.suffix}"
  resource_group_name        = azurerm_resource_group.core.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false # allows a clean teardown and rebuild
  soft_delete_retention_days = 7
  tags                       = local.tags
}

# --- Container images -------------------------------------------------------------------------
# The registry is not managed here: scripts/ops/wake-up.sh creates acrnebo<suffix> in this
# resource group and sleep.sh deletes it, so it only costs on days someone works.
# Run sleep before destroying this stack (see README).

# --- Alerts and budget ------------------------------------------------------------------------

resource "azurerm_monitor_action_group" "email" {
  name                = "ag-nebo-email"
  resource_group_name = azurerm_resource_group.core.name
  short_name          = "nebo"
  tags                = local.tags

  email_receiver {
    name                    = "owner"
    email_address           = var.notify_email
    use_common_alert_schema = true
  }
}

resource "azurerm_consumption_budget_subscription" "nebo" {
  name            = "budget-nebo"
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.budget_amount
  time_grain      = "Monthly"

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
      contact_groups = [azurerm_monitor_action_group.email.id]
    }
  }
}

# --- Email for pipeline notifications ---------------------------------------------------------

resource "azurerm_email_communication_service" "core" {
  name                = "ecs-nebo-${local.suffix}"
  resource_group_name = azurerm_resource_group.core.name
  data_location       = "Europe"
  tags                = local.tags
}

resource "azurerm_email_communication_service_domain" "azure_managed" {
  name              = "AzureManagedDomain"
  email_service_id  = azurerm_email_communication_service.core.id
  domain_management = "AzureManaged"
  tags              = local.tags
}

resource "azurerm_communication_service" "core" {
  name                = "acs-nebo-${local.suffix}"
  resource_group_name = azurerm_resource_group.core.name
  data_location       = "Europe"
  tags                = local.tags
}

resource "azurerm_communication_service_email_domain_association" "core" {
  communication_service_id = azurerm_communication_service.core.id
  email_service_domain_id  = azurerm_email_communication_service_domain.azure_managed.id
}
