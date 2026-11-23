terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  # The account comes from core/infra/backend.hcl:
  #   terraform init -backend-config="$(git rev-parse --show-toplevel)/core/infra/backend.hcl"
  # Only you can write this container (Storage Blob Data Contributor on rg-nebo-mgmt).
  backend "azurerm" {
    container_name = "tfstate-identities"
    key            = "identities.tfstate"
  }
}

provider "azurerm" {
  # The subscription comes from ARM_SUBSCRIPTION_ID, so it is never committed:
  #   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  storage_use_azuread = true

  # Registering providers needs subscription-wide rights, which nobody here has; the owner's subscription
  # already has the ones NEBo uses.
  resource_provider_registrations = "none"

  features {}
}
