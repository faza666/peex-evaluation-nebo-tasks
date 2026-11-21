# Stage A: Delivery & configuration

[Stage issue](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/1) · [close-out](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/12). There is no Kubernetes in this stage: CD deploys to Azure Container Apps, and the Task 3 pilot runs on one small VM.

| Folder | Task | Code |
|---|---|---|
| [`task1-feedback/`](task1-feedback/) | [Task 1: Feedback loop](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/4) | badges, notification emails |
| [`task2-integrations/`](task2-integrations/) | [Task 2: Third-party integrations](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/5) | `infra-aca/` (stack `aca`) |
| [`task3-config-mgmt/`](task3-config-mgmt/) | [Task 3: Configuration-management design](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/6) | `ansible/`, `infra-vm/` (stack `vm`) |

**Infrastructure:** creates `aca` and `vm`, on top of [`core`](../core/). At the end of the stage `vm` is deleted; `aca` stays for Stage B.
