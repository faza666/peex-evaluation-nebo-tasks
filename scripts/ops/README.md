# Ops scripts

Tool checks, Azure bootstrap, and the wake-up / sleep / status scripts that keep paid compute asleep unless someone is working.

| Script | Purpose |
|---|---|
| `check-tools.sh A\|B\|C` | Checks the tools a stage needs (stages are cumulative) and prints their versions. Exits 1 if a required tool is missing. For Stage A it also checks the `az` extensions, the `gh` `project` scope and `gh` sub-issue support. |
| `bootstrap-state.sh` | One-time Azure setup, safe to re-run: checks you hold Owner, registers the resource providers, creates the Terraform state storage (`rg-nebo-tfstate`, Entra ID only, versioning, soft delete) and writes `infra/backend.hcl`. |
| `send-test-email.sh` | Sends a test email through Communication Services to the notification address, without printing the address or storing the connection string. |
