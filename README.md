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
├── scripts/owner/                       PowerShell scripts for the subscription owner
├── scripts/ops/                         tool checks, state bootstrap, wake-up / sleep / status, sleep guard
├── scripts/ci/                          docker-build helpers
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

## Origin

The application is cloned from [edonosotti/ci-cd-tutorial-sample-app](https://github.com/edonosotti/ci-cd-tutorial-sample-app), written for a [RockedScience article](https://medium.com/rockedscience/docker-ci-cd-pipeline-with-github-actions-6d4cd1731030) on Medium. Its commit history is kept; everything after it is new work for these tasks.
