terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  # The account comes from core/infra/backend.hcl. mi-nebo-plan only reads this container (Storage Blob Data
  # Reader, so its plans run with -lock=false); mi-nebo-rbac is the only identity that can write it.
  backend "azurerm" {
    container_name = "tfstate-rbac"
    key            = "rbac.tfstate"
  }
}

provider "azurerm" {
  # rbac.yml signs in through GitHub OIDC and passes the client, tenant and subscription as ARM_* variables,
  # so none of them is committed.
  storage_use_azuread = true

  # Registering providers needs subscription-wide rights, which nobody here has.
  resource_provider_registrations = "none"

  features {}
}
