# DevOps Infrastructure & Deployment Guide

## Overview

This repository documents the application build and deployment workflow, AWS infrastructure, CI/CD pipeline, monitoring, alerting, and recommended production deployment practices.

The objective is to provide a consistent, secure, and repeatable deployment process while minimizing manual changes to production environments.

## Architecture Overview

The proposed deployment architecture includes:

- **Docker:** Containerize applications into reproducible images.
- **CI/CD Pipeline:** Build, test, scan, and publish application images.
- **Amazon EKS:** Run and manage containerized applications on Kubernetes.
- **Amazon RDS:** Provide managed relational database services.
- **Monitoring and Alerts:** Detect application, infrastructure, and database issues.
- **Argo CD:** Manage Kubernetes deployments through GitOps.
- **Helm:** Package and configure Kubernetes applications and reusable deployment templates.

## 1. Dockerfile and Containerization

Docker is used to package the application and its runtime dependencies into a container image.

Recommended practices:

- Use a trusted, minimal base image.
- Use multi-stage builds where appropriate.
- Run containers as a non-root user.
- Do not store credentials or secrets in the Dockerfile.
- Add a `.dockerignore` file to exclude unnecessary files.
- Pin important dependencies and base-image versions.
- Scan images for vulnerabilities before publishing them.

Example workflow:

1. Build the Docker image.
2. Run application and container tests.
3. Scan the image for vulnerabilities.
4. Tag the image with a unique version or Git commit SHA.
5. Push the approved image to Amazon ECR.

## 2. CI/CD Pipeline

The CI pipeline automates application validation, container creation, security checks, and image publishing.

### Recommended pipeline stages

1. **Source:** Trigger the pipeline when code is pushed or a pull request is opened.
2. **Validation:** Run linting and application tests.
3. **Security:** Run source-code and dependency scans, such as SonarQube and Trivy where applicable.
4. **Build:** Build the Docker image.
5. **Image Scan:** Scan the image before publishing.
6. **Publish:** Push the versioned image to Amazon ECR.
7. **GitOps Update:** Update the image version in the deployment configuration repository.
8. **Deployment:** Argo CD detects the Git change and synchronizes the Kubernetes resources according to the configured deployment policy.

Use GitHub Actions or another approved CI platform to implement the pipeline.

For AWS authentication, prefer GitHub Actions OIDC with a least-privilege IAM role instead of long-lived AWS access keys.

## 3. Amazon EKS

Amazon Elastic Kubernetes Service (EKS) provides the Kubernetes platform for running application workloads.

Recommended practices:

- Run production workloads on private worker nodes where possible.
- Restrict access to the Kubernetes API endpoint.
- Apply Kubernetes RBAC and least-privilege IAM permissions.
- Use separate development, staging, and production environments.
- Configure readiness and liveness probes.
- Set appropriate CPU and memory requests and limits.
- Use autoscaling where appropriate.
- Store application secrets in an approved secrets-management service.
- Use rolling updates and health checks to reduce deployment downtime.
- Maintain a tested rollback procedure.

Infrastructure changes should be managed through reviewed Terraform changes or another approved infrastructure-as-code workflow.

## 4. Amazon RDS

Amazon RDS provides a managed relational database for application data.

Recommended practices:

- Place the database in private subnets.
- Allow database access only from approved application security groups.
- Avoid exposing the database publicly.
- Enable encryption at rest and in transit.
- Configure backups, retention, and point-in-time recovery according to business requirements.
- Evaluate Multi-AZ deployment for production availability.
- Monitor CPU, memory-related indicators, storage, connections, latency, and database errors.
- Store database credentials securely and rotate them according to policy.
- Test database restore and recovery procedures regularly.

Database schema changes should be reviewed and coordinated with application deployments.

## 5. Monitoring and Alerts

Monitoring should cover application health, Kubernetes workloads, AWS infrastructure, and database performance.

### Application and Kubernetes monitoring

Possible tools include:

- Prometheus and Grafana for metrics and dashboards.
- Loki for log aggregation.
- Datadog where application performance monitoring and distributed tracing are required.
- Kubernetes events and health probes for workload troubleshooting.

### AWS monitoring

Use Amazon CloudWatch and relevant AWS service metrics for:

- EKS node and workload health.
- RDS CPU utilization, connections, storage, and latency.
- Application load balancer health and target errors.
- Infrastructure and application logs.
- AWS service and operational events.

### Alerting recommendations

Create actionable alerts for:

- Application availability and elevated error rates.
- High latency and failed health checks.
- Kubernetes pods repeatedly restarting or remaining unscheduled.
- Node resource exhaustion.
- RDS storage pressure, connection exhaustion, or elevated latency.
- Failed deployments and synchronization errors.
- Critical security findings.

Define alert thresholds based on workload baselines, and route notifications to the appropriate operations team. Alerts should include severity, affected service, dashboard or runbook link, and recommended troubleshooting steps.

## 6. Recommendation: Adopt Argo CD for GitOps Deployments

### Current challenge

Manual deployment commands and direct changes to production Kubernetes resources can introduce configuration drift, accidental changes, and inconsistent deployments.

### Recommended approach

Adopt Argo CD as the GitOps continuous delivery tool for Kubernetes.

Argo CD continuously compares the desired configuration in Git with the live Kubernetes environment. It can identify drift and, when configured, synchronize the cluster with the approved Git state.

### Proposed deployment workflow

1. Developers submit application changes through a pull request.
2. CI validates the code and builds a container image.
3. Security scans run before the image is published to Amazon ECR.
4. The pipeline updates the image tag in the GitOps configuration.
5. A pull request reviews and approves the deployment change.
6. Argo CD detects the approved Git change.
7. Argo CD deploys the application to the target EKS environment.
8. Monitoring and alerts verify application health.

### How Helm fits into this approach

Helm can continue to be used for packaging and templating Kubernetes resources. Argo CD can manage deployments from Helm charts stored in Git or from approved chart repositories.

**Recommended combination: Argo CD + Helm + Git-based environment configuration.**

### Production safety controls

- Require pull-request reviews for production deployment changes.
- Protect the production branch with branch protection and required checks.
- Use separate Argo CD applications or projects for different environments.
- Apply least-privilege Kubernetes permissions.
- Restrict who can modify Argo CD configuration and synchronize applications.
- Consider manual synchronization or approval gates for sensitive production changes.
- Enable automatic synchronization and self-healing only where the operational policy permits it.
- Use pruning cautiously, particularly for stateful resources.
- Monitor deployment health and document rollback procedures.

Argo CD reduces the need for direct manual changes to production Kubernetes resources, but it does not eliminate risk. Incorrect changes merged into Git can still be deployed. Review controls, permissions, health checks, and rollback procedures remain essential.

## 7. Environment Separation

Maintain separate configuration and access controls for:

- **Development:** Frequent changes and automated validation.
- **Staging:** Pre-production verification and release testing.
- **Production:** Approved releases, stricter access, and controlled synchronization.

Environment-specific configuration should be version-controlled without committing secrets.

## 8. Security and Operational Best Practices

- Apply least privilege to IAM roles and Kubernetes service accounts.
- Use OIDC for CI-to-AWS authentication where supported.
- Scan source code, dependencies, and container images.
- Protect Git branches and require reviews for sensitive changes.
- Keep secrets out of source code and container images.
- Encrypt sensitive data in transit and at rest.
- Maintain audit logs and operational runbooks.
- Regularly test backups, recovery, and rollback procedures.

## 9. Implementation Status

This document describes the intended architecture and recommended practices. The actual implementation status of Docker builds, CI security checks, EKS, RDS, monitoring, and Argo CD should be verified against the repository and AWS environment.

## Conclusion

A combination of automated CI, infrastructure as code, Amazon EKS, Amazon RDS, monitoring and alerting, and GitOps-based delivery can improve deployment consistency and operational safety.

Adopting Argo CD with Helm is recommended to make production changes reviewable, traceable, and controlled through Git rather than relying on direct manual Kubernetes modifications.
