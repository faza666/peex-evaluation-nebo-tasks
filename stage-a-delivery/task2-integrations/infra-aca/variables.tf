variable "commit" {
  description = "The commit terraform.yml runs for (TF_VAR_commit). Only a new app uses it: it starts with the image docker-build.yml pushed for this commit, sha-<7 characters>."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.commit))
    error_message = "commit must be a full 40-character commit SHA: terraform.yml sets TF_VAR_commit."
  }
}

variable "budget_amount" {
  description = "Monthly budget for rg-nebo-stage-a, in the billing currency. Container Apps stay in the free grant, and the pilot VM costs about 1."
  type        = number
  default     = 5
}

variable "budget_start_date" {
  description = "First day of the first budget month (must be the first of a month)."
  type        = string
  default     = "2026-11-01T00:00:00Z"
}
