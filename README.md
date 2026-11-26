# PeEx NEBo evaluation tasks

A small Flask REST API, a daily-menu service, used as the workload for eight DevOps evaluation tasks on Azure: CI/CD feedback and integrations, configuration management, observability, query scripts, troubleshooting, service mesh and load balancing.

**Planning and progress:** [NEBo Project](https://github.com/users/faza666/projects/1). Every piece of work is an issue with an estimate and its actual time.

## Stages

The work is delivered in three stages. Each stage creates only the infrastructure its tasks need and removes what later stages don't need.

| Stage | Tasks | Infrastructure |
|---|---|---|
| [A: Delivery & configuration](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/1) | 1 Feedback loop · 2 Third-party integrations · 3 Configuration management | `core`, Container Apps, a pilot VM |
| [B: Container operations](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/2) | 5 Observability · 4 Query scripts · 6 Troubleshooting | AKS, the VM again |
| [C: Container networking](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/3) | 7 Service mesh · 8 Load balancing | Istio on AKS, Application Gateway |

## Repository layout

The folders follow the stages. Everything the stages share is in `core/`. Each stage folder has one subfolder per task, holding that task's code, write-up and `evidence/`.

```text
.github/                                 workflows, issue forms, actions (GitHub reads them only here)
VERSION                                  the release version: CI adds the patch number
core/                                    shared across stages
├── app/                                 the Flask application: code, migrations, tests, Dockerfile
├── infra/                               Terraform stack core, plus backend.hcl for every stack
├── identities/                          Terraform stack identities: every managed identity (mi-nebo-*)
├── rbac/                                Terraform stack rbac: every role assignment, applied after the owner approves
├── scripts/owner/                       PowerShell scripts for the subscription owner
├── scripts/ops/                         tool checks, state bootstrap, wake-up / sleep / status, sleep guard
├── scripts/ci/                          docker-build and rbac helpers
└── adr/                                 architecture decision records
stage-a-delivery/
├── task1-feedback/                      badges and notification emails
├── task2-integrations/                  infra-aca/ (stack aca)
└── task3-config-mgmt/                   ansible/, infra-vm/ (stack vm), design doc
stage-b-container-ops/
├── b0-aks-base/                         infra-aks/ (stack aks), chart/ (Helm), netpol/, menu-web/
├── task5-observability/                 k8s/
├── task4-queries/                       scripts/
└── task6-troubleshooting/               write-up of the incident issues
stage-c-networking/
├── task7-service-mesh/                  k8s/ (Istio)
└── task8-load-balancing/                infra-edge/ (stack edge)
```

Start from [`core/`](core/), [`stage-a-delivery/`](stage-a-delivery/), [`stage-b-container-ops/`](stage-b-container-ops/) or [`stage-c-networking/`](stage-c-networking/): each has a README with links to its issues.

## API

| Endpoint | Response |
|---|---|
| `GET /` | `{"status": "ok"}` |
| `GET /menu` | Today's special, or 404 if there is none |
| `GET /health` | Liveness: `{"status": "ok", "version": "<APP_VERSION>"}` |
| `GET /ready` | Readiness: 200 when the database answers, 503 when it doesn't |
| `GET /metrics` | Prometheus metrics: request counts and latency per endpoint, plus `app_info{version}` |

Logs go to stdout as one JSON object per line, including gunicorn's access log.

## Running it

Everything below runs in [`core/app/`](core/app/), the application's own folder.

Locally (Python 3.8 or newer):

```sh
cd core/app
python3 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest --cov        # tests and coverage
.venv/bin/ruff check . && .venv/bin/ruff format --check .
```

In a container:

```sh
docker build --build-arg APP_VERSION=0.1.0 -t nebo-menu .
docker run --rm -p 8000:8000 nebo-menu  # migrates, seeds, then serves on :8000
```

The image is deliberately based on `python:3.8-slim`, which is end-of-life, so the security scan in Task 2 has real findings to fail on.

Configuration comes from environment variables: `DATABASE_URL` (default: SQLite inside the container), `APP_VERSION`, `LOG_LEVEL` and `PORT`.

Dependencies: edit `requirements.in` or `requirements-dev.in`, then regenerate the pinned files with the command at the top of each `.in` file.

## Project setup

Everything NEBo needs that isn't in the code: Azure access, GitHub environments, secrets and variables, and the Teams flows. This section lists names only. Values live in Azure, in GitHub settings or in the Teams flows, and never in the repository. How each stack works is in its own README.

### First-time order

| # | Who | Step | Details |
|---|---|---|---|
| 1 | Subscription owner | `1-Prepare-Subscription.ps1`: the five resource groups, and the operator's rights on `rg-nebo-mgmt` | [`core/scripts/owner/`](core/scripts/owner/) |
| 2 | Operator | `bootstrap-state.sh`: state storage, one container per state owner, `core/infra/backend.hcl` | [`core/scripts/ops/`](core/scripts/ops/) |
| 3 | Operator | Apply `core/identities`, then set the `AZURE_CLIENT_ID_*` variables from `terraform output github_variables` | [`core/identities/`](core/identities/) |
| 4 | Subscription owner | `2-Grant-Seed.ps1`: the first rights of `mi-nebo-rbac` and `mi-nebo-plan`, and the lock on `mi-nebo-rbac` | [`core/scripts/owner/`](core/scripts/owner/) |
| 5 | Operator | GitHub environments, secrets and Teams flows | below |
| 6 | Both | Every other role: a pull request to `grants.yaml`, the merge, and the subscription owner's approval | [`core/rbac/`](core/rbac/) |
| 7 | Operator | `core` from `terraform.yml`: merge, then approve in the `core` environment | [`core/infra/`](core/infra/) |

Each stage stack follows the same way: request its grants (step 6), then apply it from `terraform.yml` in its stage's environment.

### GitHub environments

An environment is what a federated credential trusts. A workflow job can sign in as an identity only if it runs in that identity's environment, and only after the environment's rules pass. So each environment decides who may act as which identity, from which branch, and whether someone must approve first.

| Environment | Job that runs in it | Signs in as | To | Required reviewer | Branches | Admin bypass |
|---|---|---|---|---|---|---|
| `rbac` | `rbac.yml` apply | `mi-nebo-rbac` | assign roles in the five NEBo groups | the subscription owner, prevent self-review on | `main` | off |
| `core` | `terraform.yml` apply and destroy of `core`, `alerts-test.yml` | `mi-nebo-core` | change `rg-nebo-core` | the operator | `main` | off |
| `stage-a` | `terraform.yml` apply and destroy of `aca` and `vm` | `mi-nebo-stage-a` | change `rg-nebo-stage-a` | the operator | `main` | off |
| `stage-b` | `terraform.yml` apply and destroy of `aks` | `mi-nebo-stage-b` | change `rg-nebo-stage-b` | the operator | `main` | off |
| `vm` | `ansible.yml` apply (#29) | `mi-nebo-config` | open SSH on the VM's NSG to the runner | the operator | `main` | off |
| `dev` | `cd.yml` deploy to `menu-dev` (#24) | `mi-nebo-cd-a`, later `mi-nebo-cd-b` | new app revisions; Helm releases in Stage B | none | any | on |
| `prod` | `cd.yml` deploy to `menu-prod` (#24) | `mi-nebo-cd-a`, later `mi-nebo-cd-b` | the same in prod; holds `PROJECT_TOKEN` (#26) | the operator | `main` | off |

- **The subscription owner's approval is the control.** `rbac` is the only environment whose approval is a second person's: everything that grants rights passes through it. `rbac.yml` checks its rules before every request and stops if one is missing.
- **The operator's approvals are a pause.** They show the plan before anything changes in Azure, so a merge never applies on its own.
- **Not every identity has an environment.** `mi-nebo-plan` (pull requests and `main`), `mi-nebo-ops` and `mi-nebo-ci` (`main`) do only read-only or routine work, so they trust a branch or pull requests, not an environment. Workload identities (`mi-nebo-menu-aca`, `mi-nebo-vm`, `mi-nebo-aks`, `mi-nebo-kubelet`, `mi-nebo-menu-wi`) are attached to Azure resources and can't be used from GitHub at all.
- **`dev` gets `main` only and admin bypass off** before `cd.yml` exists (#24).
- **`stage-c`** is created in C0, the same way as `stage-b`.

To set one up: Settings → Environments → New environment. Add the required reviewer, set Deployment branches to Selected branches with `main`, and turn off Allow administrators to bypass.

### Secrets

Every secret is a repository secret for Actions. None is stored on an environment yet.

| Secret | What it is | Used by |
|---|---|---|
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | The tenant and subscription for OIDC sign-in. They are secrets so that public logs mask them | every workflow that signs in to Azure |
| `OPERATOR_OBJECT_ID` | The operator's object ID, for the `operator` grants. From `az ad signed-in-user show --query id -o tsv` | `rbac.yml` |
| `NOTIFY_EMAIL` | The operator's work address: the Action Group's email receiver | `terraform.yml` (core), `alerts-test.yml` |
| `TEAMS_WEBHOOK_URL` | Webhook of the pipeline notifications flow | the `notify` action |
| `TEAMS_APPROVALS_WEBHOOK_URL` | Webhook of the `NEBo approvals` flow | `rbac.yml` |
| `TEAMS_ALERTS_WEBHOOK_URL` | Webhook of the alerts flow: the Action Group's webhook receiver | `terraform.yml` (core), `alerts-test.yml` |
| `SONAR_TOKEN` | SonarCloud token | `docker-build.yml` |

Planned: `PROJECT_TOKEN`, a classic token with the `project` scope, on the `prod` environment (#26).

### Variables

| Variable | What it is | Used by |
|---|---|---|
| `AZURE_CLIENT_ID_<NAME>` | Client ID of `mi-nebo-<name>`, one for each identity GitHub signs in as: `RBAC`, `PLAN`, `OPS`, `CORE`, `CI`, `STAGE_A`, `CD_A`, `CONFIG`, `STAGE_B`, `CD_B`. Client IDs aren't secret | every Azure workflow; `terraform.yml` takes the deployer's as `AZURE_CLIENT_ID_<ENVIRONMENT>` |
| `TRIVY_FAIL_ON` | Image scan gate. Unset means `CRITICAL`; `none` only reports | `docker-build.yml` |
| `TRIVY_IAC_FAIL_ON` | Terraform scan gate. Unset means `HIGH,CRITICAL`; `none` only reports | `docker-build.yml`, `terraform.yml` |

After `core/identities` adds or removes an identity, update the variables from `terraform output github_variables`.

### Teams flows

Each flow is a Teams Workflows flow: the trigger "When a Teams webhook request is received" (who can trigger: anyone), then "Post card in a chat or channel". The trigger's URL is the flow's secret. Anyone holding it can post, so it is never printed.

| Flow | Posts to | Secret | Sent by |
|---|---|---|---|
| Pipeline notifications | the operator's chat with the Flow bot | `TEAMS_WEBHOOK_URL` | the `notify` action |
| `NEBo approvals` | the chat between the operator and the subscription owner | `TEAMS_APPROVALS_WEBHOOK_URL` | `rbac.yml`: approval needed, applied or not applied |
| Alerts | the operator's own chat (group chat `48:notes`, posted as the user) | `TEAMS_ALERTS_WEBHOOK_URL` | `ag-nebo-alerts`, in the common alert schema |

**The alerts card** reads `data.essentials` from the alert: `monitorCondition`, `alertRule`, `severity`, `signalType`, `monitoringService`, `configurationItems` and `firedDateTime`.

**The Action Group's email receiver** must be verified once. Azure mails a code from `azure-noreply@microsoft.com`, and it must be entered within 30 minutes. Until then the receiver gets nothing, tests included. If the mail doesn't arrive, look in the mail quarantine, then use Resend on the Action Group in the portal.

**Testing both:** run `alerts-test.yml`. It asks Azure to send a test notification to the Action Group's receivers, so it works only after `core` has been applied with both secrets set.

### Repository settings

- **Default branch `main`:** every change arrives by squash-merging a pull request from a `<stage><n>/<slug>` branch.
- **Actions:** the default `GITHUB_TOKEN` is read-only, and workflows can't approve pull requests. Each workflow asks for the extra permissions it needs.
- **Tracker:** labels and the Project fields are described in [ADR 0001](core/adr/0001-work-tracker.md).

### Checking the setup

| What | How |
|---|---|
| Environments and their rules | `gh api repos/faza666/peex-evaluation-nebo-tasks/environments` |
| Secret and variable names | `gh secret list`, `gh variable list` |
| Every role assignment on NEBo scopes | the subscription owner's `Show-NeboAccess.ps1` |
| Drift from `grants.yaml` | `rbac.yml` checks every Monday |
| Alert delivery | `alerts-test.yml` |

## Origin

The application is cloned from [edonosotti/ci-cd-tutorial-sample-app](https://github.com/edonosotti/ci-cd-tutorial-sample-app), written for a [RockedScience article](https://medium.com/rockedscience/docker-ci-cd-pipeline-with-github-actions-6d4cd1731030) on Medium. Its commit history is kept; everything after it is new work for these tasks.
