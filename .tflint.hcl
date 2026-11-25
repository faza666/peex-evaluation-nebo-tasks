# TFLint for every Terraform stack. terraform.yml runs it in each stack folder with --config pointing here:
#   tflint --init --config="$(git rev-parse --show-toplevel)/.tflint.hcl"
#   tflint --chdir=core/infra --config="$(git rev-parse --show-toplevel)/.tflint.hcl"

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
