terraform {
  required_version = ">= 1.9, < 2.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  # Settings come from ../backend.hcl: terraform init -backend-config=../backend.hcl
  backend "azurerm" {
    key = "core.tfstate"
  }
}

provider "azurerm" {
  # The subscription comes from ARM_SUBSCRIPTION_ID, so it is never committed:
  #   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  storage_use_azuread = true

  features {
    key_vault {
      # Lets a torn-down stack be rebuilt with the same Key Vault name right away.
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}
