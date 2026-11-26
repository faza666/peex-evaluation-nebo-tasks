terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  # The account comes from core/infra/backend.hcl: terraform init -backend-config=<repo>/core/infra/backend.hcl
  # mi-nebo-stage-a writes this container (terraform.yml on main); mi-nebo-plan only reads it, for PR plans.
  backend "azurerm" {
    container_name = "tfstate-stage-a"
    key            = "aca.tfstate"
  }
}

provider "azurerm" {
  # terraform.yml signs in through GitHub OIDC and passes the client, tenant and subscription as ARM_*
  # variables, so none of them is committed.
  storage_use_azuread = true

  # Registering providers needs subscription-wide rights, which nobody here has; the owner's subscription
  # already has the ones NEBo uses.
  resource_provider_registrations = "none"

  features {}
}
