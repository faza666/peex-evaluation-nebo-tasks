# Core: shared across stages

Everything here is used by all three stages and lives until the final teardown.

| Path | Contents |
|---|---|
| [`app/`](app/) | The Flask application, used by every stage: code, migrations, tests, Dockerfile, dependencies and the Sonar settings |
| [`infra/`](infra/) | Terraform stack `core`: Log Analytics, Azure Monitor workspace, Key Vault, Action Group, budget, the GitHub OIDC identity and Communication Services Email. Also `backend.hcl`, the state backend every stack uses |
| [`scripts/ops/`](scripts/ops/) | Tool checks, Azure bootstrap, wake-up / sleep / status and the sleep guard |
| [`scripts/ci/`](scripts/ci/) | Helpers for the `docker-build` workflow: version, test report, Trivy gates, run summary |
| [`adr/`](adr/) | Architecture decision records |

`.github/` is shared too but stays at the repo root, because GitHub reads workflows, issue forms and actions only from there. So does `VERSION`: CI counts the commits since it last changed to get the patch number.
