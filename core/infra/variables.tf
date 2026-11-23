variable "location" {
  description = "Azure region for every NEBo resource."
  type        = string
  default     = "swedencentral"
}

variable "notify_email" {
  description = "Where alerts and budget warnings are emailed. Set it in the git-ignored notify.auto.tfvars; never commit it."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.notify_email))
    error_message = "notify_email must be an email address."
  }
}

variable "github_repo" {
  description = "The GitHub repository (owner/name) whose workflows may sign in to Azure through OIDC."
  type        = string
  default     = "faza666/peex-evaluation-nebo-tasks"
}

variable "github_owner_id" {
  description = "Numeric ID of the repository owner. GitHub puts it in the OIDC subject (owner@id), so a re-registered name can't inherit access."
  type        = number
  default     = 56168853
}

variable "github_repo_id" {
  description = "Numeric ID of the repository, also part of the OIDC subject (name@id)."
  type        = number
  default     = 1459147871
}

variable "budget_amount" {
  description = "Monthly budget for the subscription, in the billing currency."
  type        = number
  default     = 50
}

variable "budget_start_date" {
  description = "First day of the first budget month (must be the first of a month)."
  type        = string
  default     = "2026-11-01T00:00:00Z"
}
