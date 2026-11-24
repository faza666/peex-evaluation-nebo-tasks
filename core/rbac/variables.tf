variable "operator_object_id" {
  description = "Entra object ID of the operator: the `operator` principal in grants.yaml. rbac.yml passes it from the OPERATOR_OBJECT_ID secret (TF_VAR_operator_object_id), so it stays masked in the public logs."
  type        = string
  default     = null
  nullable    = true
  sensitive   = true

  validation {
    # coalesce() skips both null and "", so "-" means unset.
    condition     = coalesce(var.operator_object_id, "-") == "-" || can(regex("^[0-9a-fA-F-]{36}$", var.operator_object_id))
    error_message = "operator_object_id must be a GUID, or empty when no grant names the operator."
  }
}
