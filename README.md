# Go Secure CI Pipeline — GitHub Actions

## 1. Overview

This project uses GitHub Actions to automate code validation, security scanning, Docker image building, and publishing to Amazon Elastic Container Registry (ECR).

The pipeline is designed to prevent code or container images from being published when the required tests, quality gate, or security scans fail.

### CI/CD workflow

```text
Developer pushes code to master
              |
              v
      Checkout source code
              |
              v
        Setup Go 1.24
              |
              v
      Download dependencies
              |
              v
         Run unit tests
              |
              v
       SonarQube analysis
              |
              v
       Quality gate check
              |
              v
        Trivy source scan
              |
              v
      Build Docker image
       (Buildx + cache)
              |
              v
       Trivy image scan
              |
              v
       AWS authentication
            (OIDC)
              |
              v
          Login to ECR
              |
              v
      Tag image with commit SHA
              |
              v
          Push image to ECR
```

## 2. Pipeline triggers

The workflow runs when code is pushed to `master` or when a pull request targets `master`.

```yaml
on:
  push:
    branches:
      - master
  pull_request:
    branches:
      - master
```

The `code-analysis` job runs for both events. The Docker build, scan, and push job runs only for a push to `master`, after the code-analysis job succeeds.

This allows pull requests to be validated without publishing container images to ECR.

## 3. Go environment and dependencies

The pipeline uses Go 1.24.

```yaml
- name: Setup Go
  uses: actions/setup-go@v5
  with:
    go-version: ${{ env.GO_VERSION }}
    cache: true

- name: Download dependencies
  run: go mod download
```

The Go setup action also caches Go modules to reduce dependency-download time across workflow runs.

**Internal artifact repository:** To meet an organization's dependency-management policy, configure Go to download modules through its approved internal repository, such as JFrog Artifactory, Sonatype Nexus, or AWS CodeArtifact. The current workflow does not yet configure an internal `GOPROXY`; `go mod download` uses the default Go module source configuration.

## 4. Unit testing

```yaml
- name: Run unit tests
  run: go test ./...
```

This command runs Go tests across all packages in the repository.

- If the tests pass, the pipeline continues.
- If a test fails, the job fails and subsequent steps in that job do not run.
- No code-formatting check is configured.

## 5. SonarQube code analysis

SonarQube analyzes source code to identify code-quality issues, potential bugs, and maintainability concerns.

```yaml
- name: SonarQube code analysis
  uses: SonarSource/sonarqube-scan-action@v6
  env:
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
    SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}
```

Configuration:

- `SONAR_HOST_URL`: GitHub repository variable containing the SonarQube server URL.
- `SONAR_TOKEN`: GitHub Actions secret used to authenticate to SonarQube.

### Quality gate

The following step waits for the SonarQube quality gate result:

```yaml
- name: Check SonarQube quality gate
  uses: SonarSource/sonarqube-quality-gate-action@v1
  timeout-minutes: 5
  env:
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
    SONAR_HOST_URL: ${{ vars.SONAR_HOST_URL }}
```

If the quality gate fails, the `code-analysis` job fails and the dependent Docker job will not run.

## 6. Trivy source scan

Trivy scans the source repository for vulnerabilities, misconfigurations, and exposed secrets.

```yaml
- name: Trivy source vulnerability scan
  uses: aquasecurity/trivy-action@0.28.0
  with:
    scan-type: fs
    scan-ref: .
    scanners: vuln,misconfig,secret
    severity: HIGH,CRITICAL
    ignore-unfixed: true
    exit-code: '1'
    format: table
```

Important options:

| Option | Purpose |
|---|---|
| `scan-type: fs` | Scans the local filesystem |
| `scanners` | Enables vulnerability, misconfiguration, and secret scanning |
| `severity` | Reports HIGH and CRITICAL findings |
| `ignore-unfixed: true` | Excludes vulnerabilities without an available fix |
| `exit-code: '1'` | Fails the step when matching findings are detected |
| `format: table` | Displays results in a readable table |

## 7. Docker build with Buildx caching

The pipeline uses Docker Buildx and the GitHub Actions cache backend.

```yaml
- name: Setup Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build Docker image with cache
  uses: docker/build-push-action@v6
  with:
    context: .
    push: false
    tags: go-ci-demo:${{ github.sha }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
    load: true
```

### How caching works

- `cache-from: type=gha` restores previously saved BuildKit layers from the GitHub Actions cache.
- `cache-to: type=gha,mode=max` saves reusable layers, including intermediate stages of a multi-stage Docker build.
- `push: false` prevents this build step from publishing directly to a registry.
- `load: true` loads the image into the runner's local Docker engine for Trivy scanning and later ECR publishing.
- `tags` assigns the image a unique Git commit SHA.

The first build may take longer because the cache is empty. Subsequent builds can reuse unchanged layers.

For the best results, structure the Dockerfile so dependency files are copied and dependencies downloaded before application source files are copied.

## 8. Trivy Docker image scan

After the image is built, Trivy scans it for HIGH and CRITICAL vulnerabilities.

```yaml
- name: Trivy Docker image scan
  uses: aquasecurity/trivy-action@0.28.0
  with:
    image-ref: go-ci-demo:${{ github.sha }}
    scan-type: image
    scanners: vuln
    severity: HIGH,CRITICAL
    ignore-unfixed: true
    exit-code: '1'
    format: table
```

This checks the image that will be published, including applicable operating-system and application-library vulnerabilities.

If the scan fails, the AWS authentication and ECR publishing steps will not execute.

## 9. AWS authentication using OIDC

The workflow authenticates to AWS through GitHub's OpenID Connect (OIDC) integration.

```yaml
permissions:
  contents: read
  id-token: write
```

The publishing job uses:

```yaml
- name: Configure AWS credentials using OIDC
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ vars.AWS_ROLE_ARN }}
    aws-region: ${{ vars.AWS_REGION }}
```

OIDC allows GitHub Actions to obtain temporary AWS credentials by assuming an IAM role. It avoids storing long-lived AWS access keys in GitHub secrets.

### AWS prerequisites

1. Configure a GitHub OIDC identity provider in AWS IAM.
2. Create an IAM role with a trust policy restricted to the intended GitHub repository and `master` branch.
3. Grant the role only the ECR permissions required to authenticate and push images.
4. Configure the AWS role ARN and region in GitHub repository variables.

The role trust policy should restrict the `sub` claim to the intended repository and branch, rather than allowing any GitHub repository to assume the role.

## 10. Amazon ECR publishing

After AWS authentication succeeds, the pipeline logs in to ECR:

```yaml
- name: Login to Amazon ECR
  id: ecr
  uses: aws-actions/amazon-ecr-login@v2
```

The image is tagged with the ECR registry, repository name, and Git commit SHA:

```bash
docker tag \
  go-ci-demo:${IMAGE_TAG} \
  "$REGISTRY/$REPOSITORY:${IMAGE_TAG}"
```

It is then pushed:

```bash
docker push "$REGISTRY/$REPOSITORY:${IMAGE_TAG}"
```

The final image reference follows this pattern:

```text
AWS_ACCOUNT_ID.dkr.ecr.AWS_REGION.amazonaws.com/ECR_REPOSITORY:GIT_COMMIT_SHA
```

For example, a deployment pipeline can use the exact image tag to identify the source revision that was built and scanned.

## 11. GitHub repository configuration

Configure these repository variables under **Settings → Secrets and variables → Actions → Variables**:

| Variable | Description |
|---|---|
| `AWS_ROLE_ARN` | IAM role ARN assumed by GitHub Actions |
| `AWS_REGION` | AWS region containing the ECR repository |
| `ECR_REPOSITORY` | Existing ECR repository name |
| `SONAR_HOST_URL` | SonarQube server URL |

Configure this secret under **Secrets**:

| Secret | Description |
|---|---|
| `SONAR_TOKEN` | SonarQube authentication token |

If your SonarQube server is private, ensure the GitHub-hosted runner can reach it. A self-hosted runner or another approved connectivity method may be required.

## 12. Failure handling

| Failure | Expected result |
|---|---|
| Dependency download fails | Code-analysis job stops |
| Unit test fails | Code-analysis job stops |
| SonarQube scan or quality gate fails | Docker job is skipped |
| Trivy source scan fails | Docker job is skipped |
| Docker build fails | Image scan and publishing do not run |
| Trivy image scan fails | AWS authentication and ECR push do not run |
| AWS OIDC authentication fails | ECR publishing does not run |
| ECR push fails | Workflow reports failure |

## 13. Security and operational notes

- Never commit AWS access keys, SonarQube tokens, or artifact-repository credentials to source control.
- Use least-privilege IAM permissions and a tightly scoped OIDC trust policy.
- Keep Go, Docker base images, and GitHub Actions versions reviewed and updated.
- Consider pinning third-party GitHub Actions to verified full commit SHAs for stronger supply-chain security.
- Review Trivy findings regularly; ignoring unfixed vulnerabilities means those findings will not fail this configured scan.
- Ensure the Dockerfile uses a trusted, minimal runtime image and runs the application as a non-root user.
- Use the commit SHA image tag as an immutable deployment identifier; enforce ECR tag immutability if required by your release policy.

## 14. Future improvements

Potential next steps include:

- Configure the approved internal Go artifact repository.
- Publish and retain scan reports as CI artifacts.
- Add SBOM generation and image signing.
- Promote the same tested image between environments rather than rebuilding it.

---

**Summary:** This workflow validates Go code, enforces the SonarQube quality gate, scans source and container vulnerabilities, uses Buildx caching to speed up Docker builds, and publishes the scanned image to Amazon ECR using short-lived AWS credentials from OIDC.
