# None of these are secret. The resource IDs name the subscription, so they show only in the masked run log
# and in `terraform output` on your machine, never in a job summary.

output "acr_name" {
  description = "Container registry name; images are <name>.azurecr.io/menu. docker-build.yml derives the same name."
  value       = azurerm_container_registry.core.name
}

output "acr_login_server" {
  description = "Container registry login server."
  value       = azurerm_container_registry.core.login_server
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.core.name
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace, used by later stacks."
  value       = azurerm_log_analytics_workspace.core.id
}

output "monitor_workspace_id" {
  description = "Resource ID of the Azure Monitor workspace (Managed Prometheus), used by later stacks."
  value       = azurerm_monitor_workspace.core.id
}

output "action_group_id" {
  description = "Resource ID of the alerts Action Group (email + Teams), used by alert rules and budgets in later stacks."
  value       = azurerm_monitor_action_group.alerts.id
}
