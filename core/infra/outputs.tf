# None of these are secret: they become GitHub repository variables.

output "azure_client_id" {
  description = "Client ID of the GitHub OIDC identity (AZURE_CLIENT_ID)."
  value       = azurerm_user_assigned_identity.github.client_id
}

output "azure_tenant_id" {
  description = "Tenant ID (AZURE_TENANT_ID)."
  value       = data.azurerm_client_config.current.tenant_id
}

output "azure_subscription_id" {
  description = "Subscription ID (AZURE_SUBSCRIPTION_ID)."
  value       = data.azurerm_subscription.current.subscription_id
}

output "acs_endpoint" {
  description = "Communication Services endpoint used to send email (ACS_ENDPOINT)."
  value       = "https://${azurerm_communication_service.core.hostname}"
}

output "acs_sender" {
  description = "Sender address of the Azure-managed email domain (ACS_SENDER)."
  value       = "DoNotReply@${azurerm_email_communication_service_domain.azure_managed.mail_from_sender_domain}"
}

output "acr_name" {
  description = "Name of the container registry that wake-up.sh creates in rg-nebo-core; images are <name>.azurecr.io/menu."
  value       = "acrnebo${local.suffix}"
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
  description = "Resource ID of the email Action Group, used by alert rules in later stacks."
  value       = azurerm_monitor_action_group.email.id
}
