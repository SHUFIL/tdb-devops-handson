# Runbook: High memory usage and OOMKilled

**Alerts:** `ContainerHighMemoryUsage` (warning, > 85% of limit for 10 min),
`ContainerCriticalMemoryUsage` (critical, > 95% for 5 min), `ContainerOOMKilled` (warning),
`NodeHighMemoryUsage` (warning)

## What it means

The container's memory working set is close to its **limit**. When it reaches the limit the kernel kills
the process (`OOMKilled`, exit code 137) and Kubernetes restarts it. At node level, low available memory
makes the kubelet evict pods.

## Impact

- Container restarts, dropped requests and lost in-memory state.
- Repeated OOMKills become a crash loop (see [container-restart.md](container-restart.md)).
- Node pressure can evict several pods at once.

## 1. Triage (first 5 minutes)

```bash
NS=<namespace>; POD=<pod>

kubectl top pod -n $NS --containers | sort -k4 -h | tail       # memory per container
kubectl describe pod $POD -n $NS | grep -B2 -A8 "Last State"   # OOMKilled? exit 137?
kubectl get pod $POD -n $NS -o jsonpath='{.spec.containers[*].resources}'; echo
kubectl get events -n $NS --sort-by=.lastTimestamp | tail -20
```

Decide which pattern you have by looking at the pod's memory graph (Prometheus query below):

| Graph shape | Meaning |
|---|---|
| Steady climb that never drops, then a cliff at each restart | **Memory leak** |
| Jumps with traffic, drops when traffic falls | **Load-driven** usage |
| Flat but close to the limit | **Limit too low** for normal operation |
| Sudden spike at one moment | Large request/batch, bad input, big query |

```promql
container_memory_working_set_bytes{namespace="<ns>",pod="<pod>",container!=""}
```

## OOMKilled

Confirm with `kubectl describe pod`: `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`.

Common causes:

| Cause | Fix |
|---|---|
| Limit lower than normal working set | Raise the memory limit and request |
| Memory leak (growth over time) | Roll back if it began with a release; otherwise get a heap dump/profile and fix the code. Restart periodically as a stop-gap |
| JVM heap larger than the container | Size from the container: `-XX:MaxRAMPercentage=70` (do not hardcode `-Xmx` above the limit) |
| Node.js default heap too small/large | Set `--max-old-space-size` to about 75% of the limit |
| Unbounded cache, queue or buffer | Add size limits/eviction |
| Large payloads or batch jobs | Stream or paginate; give batch jobs their own, larger limits |
| Many threads/connections | Reduce pool sizes (each thread/connection costs memory) |

## Mitigation

```bash
# Raise the limit (rolls the pods). Update Git/Helm afterwards or it is overwritten.
kubectl set resources deploy/<deployment> -n $NS --requests=memory=512Mi --limits=memory=1Gi

# Spread load across more pods
kubectl scale deploy/<deployment> -n $NS --replicas=<n>

# Roll back a release that introduced the growth
kubectl rollout undo deploy/<deployment> -n $NS

# Temporary relief for a leak: rolling restart (does not fix the cause)
kubectl rollout restart deploy/<deployment> -n $NS
```

When raising a limit, make sure nodes have room (`kubectl top node`). A pod that no longer fits stays `Pending`.
Keep `requests` close to real usage; a limit far above the request lets the node become overcommitted.

## Node-level memory

For `NodeHighMemoryUsage`, `instance` is the node's IP address.

```bash
kubectl get nodes -o wide
NODE=<node-name>
kubectl describe node $NODE | grep -A8 "Conditions"            # MemoryPressure?
kubectl describe node $NODE | grep -A10 "Allocated resources"
kubectl top pod -A --sort-by=memory | head -15
kubectl get events -A --field-selector reason=Evicted           # recent evictions
```

Actions:

1. Fix or limit the largest consumer. Pods **without** memory limits are the usual cause.
2. Add capacity (the node group `desired_size` is ignored by Terraform after creation, so use the CLI):

   ```bash
   aws eks update-nodegroup-config --region ap-south-1 \
     --cluster-name eks-prod --nodegroup-name eks-prod-default \
     --scaling-config minSize=3,maxSize=6,desiredSize=4
   ```

   For a lasting fix, change the instance type (`node_instance_types`) or `node_*_size` in `terraform.tfvars` and apply.
3. For one bad node: `kubectl cordon $NODE`, then `kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data`.

## 2. Verify resolution

- `kubectl top pod -n $NS --containers` shows memory comfortably below 80% of the limit and stable.
- No new OOMKilled restarts for at least 30 minutes (`kubectl describe pod`).
- Alerts show **RESOLVED** in Slack.

## Escalate if

- OOMKills continue after raising the limit (likely a leak, so the service owner must investigate).
- Several nodes show `MemoryPressure` or pods are being evicted cluster-wide.
- Node capacity cannot be added (quotas) and pods stay `Pending`.

## Prevention

- Set memory requests and limits on **every** container (requests = typical usage, limits = peak plus headroom).
- Alert on the trend: track memory growth after each release.
- Load-test and soak-test (hours) to catch leaks before production.
- Tune runtime memory settings (JVM, Node, Go `GOMEMLIMIT`) to fit the container limit.
- Use a VPA in recommendation mode to learn right-sized values.
