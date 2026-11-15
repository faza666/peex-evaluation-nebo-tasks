# Ops scripts

Tool checks, Azure bootstrap, and the wake-up / sleep / status scripts that keep paid compute asleep unless someone is working.

| Script | Purpose |
|---|---|
| `check-tools.sh A\|B\|C` | Checks the tools a stage needs (stages are cumulative) and prints their versions. Exits 1 if a required tool is missing. For Stage A it also checks the `az` extensions, the `gh` `project` scope and `gh` sub-issue support. |
