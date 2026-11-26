# Stage A's CD target, in rg-nebo-stage-a: a Container Apps environment with the apps menu-dev and menu-prod.
# terraform.yml applies it as mi-nebo-stage-a. Terraform creates the apps; after that cd.yml, as mi-nebo-cd-a, owns
# their revisions (image, revision suffix and traffic), so Terraform ignores those three. The subscription owner
# created the resource group, and every role on it comes from core/rbac/grants.yaml.

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "stage_a" {
  name = "rg-nebo-stage-a"
}

# The apps' identity, from core/identities: AcrPull on the registry and Key Vault Secrets User, both from
# grants.yaml. mi-nebo-stage-a may attach it through its Managed Identity Operator grant.
data "azurerm_user_assigned_identity" "menu" {
  name                = "mi-nebo-menu-aca"
  resource_group_name = "rg-nebo-mgmt"
}

data "azurerm_monitor_action_group" "alerts" {
  name                = "ag-nebo-alerts"
  resource_group_name = "rg-nebo-core"
}

locals {
  subscription_id = data.azurerm_client_config.current.subscription_id
  location        = data.azurerm_resource_group.stage_a.location
  tags            = { "nebo:stack" = "aca" }

  # Names from the core stack. The registry has the same suffix as there and in docker-build.yml: the first 6 hex
  # characters of sha256(subscription ID). The workspace ID is built from its name, because reading the workspace
  # as a data source also reads its shared key, which mi-nebo-plan (Reader) may not.
  registry         = "acrnebo${substr(sha256(local.subscription_id), 0, 6)}.azurecr.io"
  log_analytics_id = "/subscriptions/${local.subscription_id}/resourceGroups/rg-nebo-core/providers/Microsoft.OperationalInsights/workspaces/law-nebo-core"

  apps = toset(["menu-dev", "menu-prod"])
}

# --- Environment ------------------------------------------------------------------------------

# Consumption only, with no VNet: the apps are public, and the consumption plan's free grant covers them. Logs go
# to the core workspace; creating that link reads the workspace key, which mi-nebo-stage-a may through its Log
# Analytics Contributor grant.
resource "azurerm_container_app_environment" "aca" {
  name                       = "cae-nebo-stage-a"
  resource_group_name        = data.azurerm_resource_group.stage_a.name
  location                   = local.location
  log_analytics_workspace_id = local.log_analytics_id
  logs_destination           = "log-analytics"
  tags                       = local.tags
}

# --- Apps -------------------------------------------------------------------------------------

# Multiple-revision mode, so cd.yml can start a revision with no traffic, test it on its own address and only then
# move the traffic. Min replicas 0: an idle app costs nothing, and the first request after a while starts it
# again (a cold start of a few seconds). The database is SQLite inside the container, so each replica migrates
# and seeds its own on start.
resource "azurerm_container_app" "menu" {
  for_each = local.apps

  name                         = each.key
  container_app_environment_id = azurerm_container_app_environment.aca.id
  resource_group_name          = data.azurerm_resource_group.stage_a.name
  revision_mode                = "Multiple"
  max_inactive_revisions       = 10
  tags                         = local.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [data.azurerm_user_assigned_identity.menu.id]
  }

  registry {
    server   = local.registry
    identity = data.azurerm_user_assigned_identity.menu.id
  }

  ingress {
    external_enabled = true
    target_port      = 8000

    # Only for the first revision. cd.yml then names the revisions that get traffic.
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    container {
      name   = "menu"
      image  = "${local.registry}/menu:sha-${substr(var.commit, 0, 7)}"
      cpu    = 0.25
      memory = "0.5Gi"

      # Startup covers the migration and seed before gunicorn listens: up to 30 s.
      startup_probe {
        transport               = "HTTP"
        path                    = "/health"
        port                    = 8000
        interval_seconds        = 2
        failure_count_threshold = 15
      }

      liveness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8000
      }

      readiness_probe {
        transport               = "HTTP"
        path                    = "/ready"
        port                    = 8000
        interval_seconds        = 5
        success_count_threshold = 1
      }
    }
  }

  lifecycle {
    # cd.yml owns these after the first apply.
    ignore_changes = [
      template[0].container[0].image,
      template[0].revision_suffix,
      ingress[0].traffic_weight,
    ]
  }
}

# --- Budget -----------------------------------------------------------------------------------

# The one budget on rg-nebo-stage-a, for the aca and vm stacks together: aca lives longer, so it owns it.
resource "azurerm_consumption_budget_resource_group" "stage_a" {
  name              = "budget-nebo-stage-a"
  resource_group_id = data.azurerm_resource_group.stage_a.id
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
      contact_groups = [data.azurerm_monitor_action_group.alerts.id]
    }
  }
}
