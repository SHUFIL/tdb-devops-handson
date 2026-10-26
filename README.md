# Runbooks

Every alert carries a `runbook_url` annotation that points to one of these files.
Set `runbook_base_url` in `envs/<env>/terraform.tfvars` to wherever this folder is browsable
(for example the GitHub `blob/main/docs/runbooks` URL).

## Alert catalog

| Alert | Severity | Fires when | Runbook |
|---|---|---|---|
| `ContainerRestartingFrequently` | warning | > 3 restarts in 15 min (1 min hold) | [container-restart.md](container-restart.md) |
| `ContainerCrashLoopBackOff` | critical | container in CrashLoopBackOff for 5 min | [container-restart.md](container-restart.md#crashloopbackoff) |
| `ContainerOOMKilled` | warning | container killed for exceeding memory limit and restarted | [high-memory.md](high-memory.md#oomkilled) |
| `ContainerHighCPUUsage` | warning | CPU > 85% of limit for 10 min | [high-cpu.md](high-cpu.md) |
| `ContainerCriticalCPUUsage` | critical | CPU > 95% of limit for 5 min | [high-cpu.md](high-cpu.md) |
| `NodeHighCPUUsage` | warning | node CPU > 85% for 10 min | [high-cpu.md](high-cpu.md#node-level-cpu) |
| `ContainerHighMemoryUsage` | warning | working set > 85% of limit for 10 min | [high-memory.md](high-memory.md) |
| `ContainerCriticalMemoryUsage` | critical | working set > 95% of limit for 5 min | [high-memory.md](high-memory.md) |
| `NodeHighMemoryUsage` | warning | node memory > 85% for 10 min | [high-memory.md](high-memory.md#node-level-memory) |

Thresholds are variables in `modules/monitoring/variables.tf`. Rules live in
`modules/monitoring/rules/container-alerts.yaml.tftpl`.

> Pod-level CPU/memory alerts only work for containers that **have resource limits set**.
> A container without limits never triggers them. Node-level alerts still cover the node.

## Severity and response targets

| Severity | Slack channel (prod) | Meaning | Respond within | Repeat reminder |
|---|---|---|---|---|
| critical | `#alerts-prod-critical` | Service is down or about to be | 15 min, any hour | every 1 h |
| warning | `#alerts-prod-warning` | Degrading or at risk, no outage yet | next business hour | every 4 h |

A `critical` alert for a container automatically silences the `warning` for the same container.

## Working an alert (all runbooks)

1. **Acknowledge** in the Slack thread so others know you own it.
2. **Identify** the cluster, namespace, pod and container from the alert text.
3. **Check for a recent change** (deploy, config, traffic). Most incidents follow a change.
4. **Stabilise first**, root-cause later: roll back, scale out, or raise a limit.
5. **Verify** the alert resolves (Slack sends a "RESOLVED" message).
6. **Record** what happened and follow up on prevention items.

## Handy access

```bash
# pick the right cluster first
aws eks update-kubeconfig --region ap-south-1 --name eks-prod
kubectl config current-context

# Alertmanager UI (silences, alert state)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Prometheus UI (run PromQL, see rule state under Alerts)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

To silence a noisy alert during planned work, open the Alertmanager UI (http://localhost:9093),
click **Silences, New Silence**, match on `alertname` and `namespace`, and set an expiry.
Always add a comment and a short expiry.

## Escalation

1. Primary on-call (platform team)
2. Service owner for the affected namespace (see the `team` label on the Deployment)
3. Engineering manager, if a customer-facing outage lasts more than 30 minutes

Fill in names, rota links and phone numbers for your team here.
