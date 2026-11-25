terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  # The account comes from backend.hcl in this folder: terraform init -backend-config=backend.hcl
  # mi-nebo-core writes this container (terraform.yml on main); mi-nebo-plan only reads it, for PR plans.
  backend "azurerm" {
    container_name = "tfstate-core"
    key            = "core.tfstate"
  }
}

provider "azurerm" {
  # terraform.yml signs in through GitHub OIDC and passes the client, tenant and subscription as ARM_*
  # variables, so none of them is committed.
  storage_use_azuread = true

  # Registering providers needs subscription-wide rights, which nobody here has; the owner's subscription
  # already has the ones NEBo uses.
  resource_provider_registrations = "none"

  features {
    key_vault {
      # Both need rights on the subscription's deleted vaults, which mi-nebo-core doesn't have. A destroyed
      # vault stays soft-deleted for 7 days, so a rebuild within that time needs a new name.
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = false
    }
  }
}
