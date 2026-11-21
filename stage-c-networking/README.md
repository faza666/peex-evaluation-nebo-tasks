# Stage C: Container networking

[Stage issue](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/3) · [close-out](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/14). Networking only, on top of the Stage B cluster.

| Folder | Task | Code |
|---|---|---|
| [`task7-service-mesh/`](task7-service-mesh/) | [Task 7: Service mesh](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/10) | `k8s/` (Istio add-on on `aks`) |
| [`task8-load-balancing/`](task8-load-balancing/) | [Task 8: Load balancing](https://github.com/faza666/peex-evaluation-nebo-tasks/issues/11) | `infra-edge/` (stack `edge`: Application Gateway) |

**Infrastructure:** turns on Istio in `aks` and creates `edge`. At the end of the stage **everything** is deleted, including `core`.
