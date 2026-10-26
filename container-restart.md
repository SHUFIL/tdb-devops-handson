# Runbook: Container restarts

**Alerts:** `ContainerRestartingFrequently` (warning), `ContainerCrashLoopBackOff` (critical)
**Related:** `ContainerOOMKilled` is covered in [high-memory.md](high-memory.md#oomkilled)

## What it means

Kubernetes keeps restarting a container because it exits, fails its liveness probe, or is killed.
In `CrashLoopBackOff` the kubelet waits longer between each retry (10s, 20s, 40s ... up to 5 min), so
the service may be partly or fully unavailable.

## Impact

- Fewer healthy replicas, so higher load on the rest and possible errors/latency for users.
- With a single replica, the service is down between restarts.
- Restarting pods may drop in-flight requests and lose in-memory state.

## 1. Triage (first 5 minutes)

```bash
NS=<namespace>; POD=<pod>

kubectl get pod $POD -n $NS -o wide                 # RESTARTS, STATUS, NODE, AGE
kubectl describe pod $POD -n $NS                    # events, Last State, probes, limits
kubectl get events -n $NS --sort-by=.lastTimestamp | tail -20
```

In `describe`, check the container's **Last State** for `Reason` and `Exit Code`.

| Reason / Exit code | Meaning | Go to |
|---|---|---|
| `OOMKilled` / 137 | Exceeded memory limit | [high-memory.md](high-memory.md#oomkilled) |
| `Error` / 1 | Application crashed | Step 2 (logs) |
| `Error` / 137 without OOMKilled | Killed by liveness probe, node, or `kill -9` | Check probe events and node |
| `Error` / 139 | Segmentation fault | App/native library bug, roll back |
| `Error` / 143 | Got SIGTERM (normal shutdown or eviction) | Check evictions and rollouts |
| `Error` / 126 or 127 | Command not executable / not found | Wrong image, entrypoint or args |
| `Completed` / 0 | Process exits normally but pod expects a long-running process | Wrong `command`, or should be a Job |
| `CreateContainerConfigError` | Missing ConfigMap/Secret/key | Step 3, config |
| `ImagePullBackOff` | Bad image tag or registry auth | Check image name, ECR permissions |

## 2. Read the logs

```bash
kubectl logs $POD -n $NS -c <container> --previous    # logs from the crashed run
kubectl logs $POD -n $NS -c <container> --tail=200    # current run
kubectl logs -n $NS deploy/<deployment> --all-containers --tail=100
```

Look for stack traces, "connection refused/timeout", "permission denied", "missing env var",
"address already in use", and out-of-memory messages.

## 3. Find the cause

| Symptom | Likely cause | Fix |
|---|---|---|
| Started right after a deploy | Bad release or config | **Roll back** (see Mitigation) |
| Logs: cannot connect to DB / dependency | Dependency down, wrong endpoint or credentials, security group | Check RDS status and endpoint; confirm the DB secret in Secrets Manager; confirm nodes can reach port 5432 |
| Logs: missing env var / config key | ConfigMap or Secret changed or deleted | `kubectl get cm,secret -n $NS`; restore the value |
| Events: `Liveness probe failed` | Probe too strict, or app is slow to start | Add a `startupProbe`; raise `initialDelaySeconds`/`timeoutSeconds`/`failureThreshold` |
| Restarts only on one node | Node problem (disk, memory pressure, network) | `kubectl describe node <node>`; cordon and drain it |
| Restart count rises slowly and regularly | Memory leak or periodic crash | See [high-memory.md](high-memory.md); check the pod's memory graph |
| Many pods restarting at once | Shared dependency failure, or cluster issue | Check DB, DNS (`coredns` pods), node health |

Check cluster basics when several services are affected:

```bash
kubectl get nodes
kubectl get pods -n kube-system
kubectl top nodes
```

## Mitigation

```bash
# Roll back the most recent release
kubectl rollout history deploy/<deployment> -n $NS
kubectl rollout undo deploy/<deployment> -n $NS
kubectl rollout status deploy/<deployment> -n $NS

# Keep serving while you investigate: add replicas (if the app is stateless)
kubectl scale deploy/<deployment> -n $NS --replicas=<n>

# Last resort for a single wedged pod (the Deployment recreates it)
kubectl delete pod $POD -n $NS
```

Do not just delete pods repeatedly: it hides the cause and resets the restart counter.
If you changed anything with `kubectl`, make the same change in Git/Helm afterwards or the next deploy will undo it.

## 4. Verify resolution

- `kubectl get pod -n $NS` shows `Running` with a restart count that no longer increases for at least 15 minutes.
- The alert shows **RESOLVED** in Slack.
- The service's health check or error rate is back to normal.

## Escalate if

- The service has been fully down for more than 15 minutes.
- Rolling back did not help, or the cause is in a shared component (DB, DNS, nodes).
- You cannot identify the cause within 30 minutes.

## Prevention

- Add readiness, liveness **and startup** probes with realistic timings.
- Set memory/CPU requests and limits from observed usage.
- Run at least 2 replicas with a PodDisruptionBudget for important services.
- Fail fast with a clear log line on bad configuration, and validate config in CI.
- Use staged rollouts and watch `kubectl rollout status` after every deploy.

## Useful PromQL

```promql
# restarts in the last hour, per container
increase(kube_pod_container_status_restarts_total[1h]) > 0

# why was the container last terminated
kube_pod_container_status_last_terminated_reason == 1
```
