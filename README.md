# Go CI Demo — Helm Deployment

## Overview

This Helm chart deploys the Go application to Kubernetes with environment-specific configuration, rolling updates, health probes, autoscaling, and disruption protection.

### Features

- Separate development and production values.
- Production starts with at least 3 replicas.
- Rolling updates designed to avoid downtime.
- Horizontal Pod Autoscaler (HPA) for CPU-based scaling.
- PodDisruptionBudget (PDB) to help maintain availability during node maintenance.
- Separate ConfigMaps and externally managed Kubernetes Secrets.
- Docker images pulled from Amazon ECR using commit SHA tags.

## Chart Structure

```text
helm/go-ci-demo/
├── Chart.yaml
├── values.yaml
├── values-dev.yaml
├── values-prod.yaml
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    ├── configmap.yaml
    ├── hpa.yaml
    └── pdb.yaml
```

## Prerequisites

- Kubernetes cluster with `kubectl` configured.
- Helm 3 installed.
- Application image published to Amazon ECR.
- Required Kubernetes Secrets created separately.
- Metrics Server available if HPA is enabled.

## Deploy the Chart

Assuming your chart is at `helm/go-ci-demo/` and the ECR image has already passed CI security checks:

### Development

```bash
helm upgrade --install go-ci-demo-dev ./helm/go-ci-demo \
  --namespace dev \
  --create-namespace \
  -f helm/go-ci-demo/values-dev.yaml \
  --set image.tag=<IMAGE_SHA>
```

### Production

```bash
helm upgrade --install go-ci-demo ./helm/go-ci-demo \
  --namespace prod \
  --create-namespace \
  -f helm/go-ci-demo/values-prod.yaml \
  --set image.tag=<IMAGE_SHA> \
  --wait \
  --timeout 5m
```

Replace `<IMAGE_SHA>` with the exact commit SHA tag pushed to ECR by your CI pipeline.

## Validate the Release

```bash
# Check the Helm release
helm list -n prod

# Check rollout status
kubectl rollout status deployment/go-ci-demo -n prod

# Check pods and their node placement
kubectl get pods -n prod -o wide

# Check autoscaling
kubectl get hpa -n prod

# Check disruption budget
kubectl get pdb -n prod

# Check application logs
kubectl logs -n prod deployment/go-ci-demo
```

### Test a Rolling Update

Deploy a new image SHA, then verify the rollout:

```bash
kubectl rollout status deployment/go-ci-demo -n prod
kubectl rollout history deployment/go-ci-demo -n prod
```

## Configuration and Secrets

- Use `values-dev.yaml` for development and `values-prod.yaml` for production.
- Store non-sensitive configuration in Kubernetes ConfigMaps.
- Create secrets separately using an approved secret-management process, such as AWS Secrets Manager with External Secrets Operator.
- Never commit secret values to Git.

## Validate the Chart

Before deploying, check the chart and rendered manifests:

```bash
helm lint ./helm/go-ci-demo

helm template go-ci-demo ./helm/go-ci-demo \
  -f helm/go-ci-demo/values-prod.yaml
```

**Production note:** Zero downtime depends on successful readiness checks, sufficient cluster capacity, and graceful application shutdown. A PodDisruptionBudget helps with voluntary disruptions such as node drains but does not protect against sudden node failures.
