# Runbook: High CPU usage

**Alerts:** `ContainerHighCPUUsage` (warning, > 85% of limit for 10 min),
`ContainerCriticalCPUUsage` (critical, > 95% for 5 min), `NodeHighCPUUsage` (warning)

## What it means

A container is using close to its CPU **limit**. Kubernetes throttles a container at its limit, so
requests slow down even though the pod is "Running". At node level, a busy node slows every pod on it.

## Impact

- Higher latency and timeouts, slower queue processing, failing health checks (which can trigger restarts).
- At node level, pods may be starved and new pods may not schedule.

## 1. Triage (first 5 minutes)

```bash
NS=<namespace>; POD=<pod>

kubectl top pod -n $NS --containers | sort -k3 -h | tail      # CPU per container
kubectl top node                                                # node pressure
kubectl get hpa -n $NS                                          # is autoscaling at max?
kubectl get deploy -n $NS                                       # replica counts
kubectl rollout history deploy/<deployment> -n $NS              # recent deploys
```

Questions to answer:

1. **Is it one pod or all replicas?** One pod suggests a stuck loop or a hot key; all replicas suggest load or a bad release.
2. **Did it start after a deploy?** If yes, suspect the release.
3. **Did traffic increase?** Check request rate on your ingress/load balancer or app metrics.
4. **Is the pod throttled?** Use the PromQL below.

## 2. Find the cause

| Pattern | Likely cause | Action |
|---|---|---|
| All replicas high, traffic up | Genuine load | Scale out (Mitigation) |
| Started after deploy | Regression (loop, expensive query, debug logging) | Roll back |
| One pod only | Stuck thread, runaway job, hot partition | Capture a profile/thread dump if possible, then restart that pod |
| HPA at `maxReplicas` | HPA ceiling too low | Raise `maxReplicas` |
| HPA not scaling | HPA has no CPU **requests** to calculate from, or metrics-server missing | Set requests; `kubectl get apiservice v1beta1.metrics.k8s.io` |
| Steady high CPU, healthy traffic | Limit set too low | Raise limit and request (see below) |
| CPU spikes on a schedule | Cron job, batch, GC | Move the schedule, give it its own limits |
| JVM / Node app using a lot of CPU in GC | Memory pressure also present | Check [high-memory.md](high-memory.md) |

Check throttling in Prometheus (a value near 1 means heavily throttled):

```promql
sum by (namespace,pod,container) (rate(container_cpu_cfs_throttled_periods_total[5m]))
/
sum by (namespace,pod,container) (rate(container_cpu_cfs_periods_total[5m]))
```

See actual usage versus limit:

```promql
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="<ns>",container!=""}[5m]))
```

## Mitigation

```bash
# Add replicas now
kubectl scale deploy/<deployment> -n $NS --replicas=<n>

# Raise the HPA ceiling
kubectl patch hpa <hpa> -n $NS --patch '{"spec":{"maxReplicas":<n>}}'

# Raise the CPU limit (rolls the pods). Update Git/Helm afterwards.
kubectl set resources deploy/<deployment> -n $NS --requests=cpu=500m --limits=cpu=1

# Roll back a bad release
kubectl rollout undo deploy/<deployment> -n $NS
```

Scaling out only helps if the nodes have room. If new pods stay `Pending`, scale the node group (below).

## Node-level CPU

For `NodeHighCPUUsage`, `instance` is the node's IP address.

```bash
kubectl get nodes -o wide                                   # map IP -> node name
NODE=<node-name>
kubectl describe node $NODE | grep -A8 "Allocated resources"
kubectl get pods -A -o wide --field-selector spec.nodeName=$NODE
kubectl top pod -A --sort-by=cpu | head -15
```

Actions, in order of preference:

1. Fix or scale the top consumer found above.
2. Add node capacity. `desired_size` is ignored by Terraform after creation, so scale with the CLI,
   and then raise `node_min_size`/`node_max_size` in `terraform.tfvars` if needed:

   ```bash
   aws eks update-nodegroup-config --region ap-south-1 \
     --cluster-name eks-prod --nodegroup-name eks-prod-default \
     --scaling-config minSize=3,maxSize=6,desiredSize=4
   ```

3. For one misbehaving node: `kubectl cordon $NODE` then `kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data`.
   Draining evicts pods, so make sure other nodes have room and PodDisruptionBudgets allow it.

## 3. Verify resolution

- `kubectl top pod -n $NS --containers` shows usage comfortably below 80% of limit.
- Throttling ratio is near 0.
- Latency and error rate are back to normal, and the alert shows **RESOLVED**.

## Escalate if

- Critical alert persists after scaling out and rolling back.
- Nodes cannot be scaled (quota/capacity) or pods remain `Pending`.
- The cause is in application code and you need the service owner.

## Prevention

- Set CPU **requests** from real usage so the scheduler and HPA behave correctly.
- Configure an HPA (target ~60-70% CPU) with a sensible `maxReplicas`.
- Load-test before launches and sizing changes.
- Review CPU limits regularly; consider removing CPU limits (keeping requests) for latency-sensitive services.
- Profile hot code paths, and cache or batch expensive work.
