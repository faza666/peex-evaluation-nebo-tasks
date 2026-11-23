# Stage B: Container operations on AKS

[Stage issue](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/2) · [close-out](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/13). AKS exists for the first time. The incidents met while setting it up become the Task 6 cases, and its logs and metrics are what the Task 4 queries run against.

| Folder | Item | Code |
|---|---|---|
| [`b0-aks-base/`](b0-aks-base/) | B0: AKS base, shared by the stage's tasks | `infra-aks/` (stack `aks`), `chart/` (Helm), `netpol/`, `menu-web/` |
| [`task5-observability/`](task5-observability/) | [Task 5: Observability](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/7) | `k8s/` |
| [`task4-queries/`](task4-queries/) | [Task 4: Query scripts](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/8) | `scripts/` |
| [`task6-troubleshooting/`](task6-troubleshooting/) | [Task 6: Troubleshooting](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/9) | write-up only; the incidents are issues |

**Infrastructure:** creates `aks` (no mesh) and `vm` again, now monitored. At the end of the stage `vm` and `aca` are deleted, and AKS goes to sleep.
