# Production Dockerfile — Go Application

## Overview

This Dockerfile builds a small, production-ready Go application image using a multi-stage Docker build.

It is designed to reduce image size, minimize the attack surface, and retrieve Go dependencies from an internal artifact repository instead of downloading them directly from the public internet.

## Docker Build Stages

### Stage 1: Builder

Base image: `golang:1.24-alpine`

The builder stage:

- Uses an internal Go module proxy through the `GOPROXY` environment variable.
- Downloads dependencies using `go mod download`.
- Builds a statically linked Linux binary.
- Uses `-trimpath` to remove local filesystem paths.
- Uses `-ldflags="-s -w"` to reduce binary size.

The internal artifact repository must be reachable from the Docker build environment and configured with the required authentication.

### Stage 2: Production Runtime

Base image: `gcr.io/distroless/static-debian12:nonroot`

The runtime stage:

- Copies only the compiled application binary.
- Excludes the Go compiler and build tools.
- Uses a minimal Distroless image.
- Runs the application as a non-root user (`65532:65532`).
- Exposes port `8080`.

## Prerequisites

- Docker installed.
- Access to the internal Go artifact repository.
- A valid `go.mod` file.
- A committed `go.sum` file when dependencies require it.
- Network access to the internal repository from the build environment.

## Internal Artifact Repository

Configure `GOPROXY` to point to the approved internal Go module proxy.

Example:

```bash
GOPROXY=https://artifactory.example.com/artifactory/api/go/go-virtual
```

Replace the example URL with your actual repository endpoint.

The Docker build should use secure authentication for private dependencies. Do not store credentials directly in the Dockerfile or commit them to Git.

Keep dependency checksum verification enabled where supported by your organization's configuration. Configure an approved internal checksum database if public checksum access is prohibited.

## Build the Docker Image

Build the image from the directory containing the Dockerfile:

```bash
docker build -t go-ci-demo:local .
```

## Run the Container

```bash
docker run -d \
  --name go-ci-demo \
  -p 8080:8080 \
  go-ci-demo:local
```

## Test the Application

```bash
curl http://localhost:8080/health
```

## Verify the Non-Root User

```bash
docker image inspect go-ci-demo:local \
  --format '{{.Config.User}}'
```

Expected output:

```text
65532:65532
```

## View Logs

```bash
docker logs go-ci-demo
```

## Clean Up

```bash
docker rm -f go-ci-demo
```

## Security and Optimization Benefits

- Multi-stage build keeps build tools out of the runtime image.
- Distroless reduces the runtime attack surface.
- Non-root execution reduces privileges.
- Internal artifact proxy centralizes dependency access.
- `go.sum` supports dependency integrity verification.
- Trivy can scan the final image for vulnerabilities.
- The resulting image can be published to Amazon ECR and deployed to Kubernetes.

## Important Notes

- The Dockerfile targets Linux AMD64; adjust the architecture if required.
- The internal artifact repository must be accessible during the build.
- Use Docker BuildKit secret mounts or an approved credential mechanism for private repository authentication.
- Pin production base images to reviewed versions or digests.
- The final runtime image does not contain a shell, so use Docker or Kubernetes tooling to inspect logs and troubleshoot the application.
