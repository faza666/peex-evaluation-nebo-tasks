variable "github_repo" {
  description = "The GitHub repository (owner/name) whose workflows may sign in through OIDC."
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

variable "aks_oidc_issuer" {
  description = "OIDC issuer URL of the AKS cluster (Stage B). Until it is set, the `kubernetes` trusts in identities.yaml are skipped. Pass it on the command line or in a git-ignored *.tfvars file; it contains the tenant ID."
  type        = string
  default     = null
  nullable    = true
}
