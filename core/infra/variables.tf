# The two addresses reach Terraform as TF_VAR_ values from GitHub secrets in terraform.yml (NOTIFY_EMAIL and
# TEAMS_ALERTS_WEBHOOK_URL); neither is ever committed or printed.

variable "notify_email" {
  description = "Where alerts and budget warnings are emailed: the operator's work address, from the secret NOTIFY_EMAIL."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.notify_email))
    error_message = "notify_email must be an email address: is the secret NOTIFY_EMAIL set?"
  }
}

variable "alerts_webhook_url" {
  description = "Teams Workflows webhook for Azure Monitor alerts, from the secret TEAMS_ALERTS_WEBHOOK_URL. Empty: email only."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.alerts_webhook_url == "" || startswith(var.alerts_webhook_url, "https://")
    error_message = "alerts_webhook_url must be an https:// URL, or empty."
  }
}

variable "budget_amount" {
  description = "Monthly budget for rg-nebo-core, in the billing currency. The registry alone is about 5."
  type        = number
  default     = 10
}

variable "budget_start_date" {
  description = "First day of the first budget month (must be the first of a month)."
  type        = string
  default     = "2026-11-01T00:00:00Z"
}
