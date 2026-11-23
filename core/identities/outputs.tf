# None of these are secret. Client IDs become GitHub repository variables; principal IDs are what role
# assignments point at (core/rbac reads them itself).

output "github_variables" {
  description = "GitHub repository variables for the identities workflows sign in as: AZURE_CLIENT_ID_<NAME> => client ID."
  value = {
    for name, identity in azurerm_user_assigned_identity.this :
    "AZURE_CLIENT_ID_${upper(replace(trimprefix(name, "mi-nebo-"), "-", "_"))}" => identity.client_id
    if length(local.identities[name].github) > 0
  }
}

output "principal_ids" {
  description = "Principal (object) ID of every identity, by name."
  value       = { for name, identity in azurerm_user_assigned_identity.this : name => identity.principal_id }
}

output "federated_subjects" {
  description = "Every trusted subject, by credential, for review."
  value = merge(
    { for key, c in azurerm_federated_identity_credential.github : key => c.subject },
    { for key, c in azurerm_federated_identity_credential.kubernetes : key => c.subject },
  )
}
