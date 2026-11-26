# Not secret: the apps are public. cd.yml reads the same addresses from Azure.

output "urls" {
  description = "Public address of each app, for the traffic it gets from cd.yml."
  value       = { for name, app in azurerm_container_app.menu : name => "https://${app.ingress[0].fqdn}" }
}

output "environment_domain" {
  description = "Default domain of the Container Apps environment; a revision's own address is <app>--<suffix>.<domain>."
  value       = azurerm_container_app_environment.aca.default_domain
}
