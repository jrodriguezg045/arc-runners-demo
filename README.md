# GitHub Actions Runner Scale Set Demo

A portable local Proof of Concept (POC) demonstrating **GitHub Actions Runner Scale Sets (ARC)** running on a local **Kubernetes cluster managed by Kind**.

The project uses Docker Compose to bootstrap the complete environment, allowing the demo to be reproduced on different machines and CPU architectures without requiring a pre-existing Kubernetes cluster.

The GitHub repository used by the runner scale set is configurable through environment variables, so the demo can be used with your own GitHub repository and Personal Access Token.

## Architecture

```text
                    GitHub

                      │

                      │ GitHub Actions
                      ▼

             ┌──────────────────┐
             │   ARC Controller │
             │                  │
             │   arc-systems    │
             └────────┬─────────┘
                      │
                      │ manages
                      ▼
             ┌──────────────────┐
             │ Runner Scale Set │
             │  arc-runner-set  │
             └────────┬─────────┘
                      │
             ┌────────┼────────┐
             ▼        ▼        ▼
          Runner   Runner   Runner
           Pod      Pod      Pod
             │        │        │
             └────────┼────────┘
                      │
                      ▼
                GitHub Actions
```

The Kubernetes cluster runs locally inside Docker using Kind.

```text
┌──────────────────────────────────────────────┐
│                 Docker                       │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ Kind Kubernetes Cluster                │  │
│  │                                        │  │
│  │  ┌──────────────────────────────────┐  │  │
│  │  │ Control Plane                    │  │  │
│  │  │                                  │  │  │
│  │  │ Kubernetes API                   │  │  │
│  │  │ ARC Controller                   │  │  │
│  │  │ Runner Scale Set                 │  │  │
│  │  │ Runner Pods                      │  │  │
│  │  └──────────────────────────────────┘  │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ demo-arc-setup                         │  │
│  │ Bootstrap container                    │  │
│  │                                        │  │
│  │ Docker CLI                             │  │
│  │ Kind                                   │  │
│  │ kubectl                                │  │
│  │ Helm                                   │  │
│  └────────────────────────────────────────┘  │
│                                              │
└──────────────────────────────────────────────┘
```

## What This Demo Shows

The POC demonstrates that:

* A Kubernetes cluster can be created automatically with Kind.
* ARC can be installed without an existing Kubernetes environment.
* GitHub Actions can dynamically request self-hosted runners.
* ARC creates ephemeral runner pods.
* Runner capacity can scale based on pending GitHub Actions jobs.
* Runner pods are removed after jobs complete.
* The entire environment can be reproduced with Docker Compose.
* The setup supports both `amd64` and `arm64` hosts.
* The GitHub repository used by ARC can be configured without modifying the project files.

## Requirements

You only need:

* Docker
* Docker Compose
* A GitHub repository
* A GitHub Personal Access Token (PAT)

The setup container installs the remaining tools automatically:

* Kind
* kubectl
* Helm

## GitHub Configuration

The demo uses two environment variables:

```bash
export GITHUB_CONFIG_URL="https://github.com/OWNER/REPOSITORY"
export GITHUB_PAT="your_github_token"
```

### GITHUB_CONFIG_URL

`GITHUB_CONFIG_URL` specifies the GitHub repository where the runner scale set will be registered.

For example:

```bash
export GITHUB_CONFIG_URL="https://github.com/YOUR_USERNAME/arc-runners-demo"
```

This allows the same POC to be used with different GitHub repositories without changing the Kubernetes configuration.

### GITHUB_PAT

`GITHUB_PAT` is used by ARC to authenticate with GitHub.

```bash
export GITHUB_PAT="your_github_token"
```

The token must have the permissions required by GitHub Actions Runner Scale Sets for the target repository.

**Never commit the token to the repository.**

## Using Your Own Repository

For the most portable setup, fork this repository into your own GitHub account.

For example:

```text
Original:

github.com/jrodriguezg045/arc-runners-demo

Your fork:

github.com/YOUR_USERNAME/arc-runners-demo
```

Then configure the demo to use your fork:

```bash
export GITHUB_CONFIG_URL="https://github.com/YOUR_USERNAME/arc-runners-demo"
export GITHUB_PAT="your_github_token"
```

Start the environment:

```bash
docker compose up
```

The GitHub Actions workflows in your fork can then use:

```yaml
runs-on: arc-runner-set
```

The complete flow becomes:

```text
Your GitHub Repository
        │
        │ GitHub Actions
        ▼
GitHub Runner Scale Set
        │
        ▼
ARC Controller
        │
        ▼
Local Kubernetes / Kind
        │
        ▼
Ephemeral Runner Pod
        │
        ▼
GitHub Actions Job
```

## Project Structure

```text
.

├── .github/
│   └── workflows/
│       └── demo-test.yml
│
├── kubernetes/
│   └── runner-values.yaml
│
├── docker-compose.yml
├── entrypoint.sh
├── destroy.sh
└── README.md
```

## Configuration

The main ARC runner configuration is located at:

```text
kubernetes/runner-values.yaml
```

The repository URL is intentionally **not hardcoded** in this file.

The target GitHub repository is supplied at runtime through:

```bash
GITHUB_CONFIG_URL
```

The GitHub authentication token is supplied through:

```bash
GITHUB_PAT
```

The current runner configuration is:

```yaml
runnerScaleSetName: "arc-runner-set"

minRunners: 1
maxRunners: 3

template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        command:
          - /home/runner/run.sh

        resources:
          requests:
            cpu: "500m"
            memory: "512Mi"

          limits:
            cpu: "1"
            memory: "1Gi"
```

## Runner Scaling

The demo currently uses:

```yaml
minRunners: 1
maxRunners: 3
```

This means:

* One runner is maintained as baseline capacity.
* ARC can create additional runners when jobs are queued.
* Up to three runners can run concurrently.
* Ephemeral runners are removed after their jobs complete.

The baseline runner also helps demonstrate the difference between having an immediately available runner and provisioning runners from zero.

The scaling model is:

```text
No workload
     │
     ▼
1 runner ready
     │
     │ additional jobs
     ▼
ARC creates more runners
     │
     ▼
2 → 3 runners
     │
     │ jobs complete
     ▼
Runner capacity returns
     │
     ▼
1 runner
```

## Start the Demo

From the project directory:

```bash
export GITHUB_CONFIG_URL="https://github.com/YOUR_USERNAME/YOUR_REPOSITORY"
export GITHUB_PAT="your_github_token"

docker compose up
```

The setup container will:

1. Install the required CLI tools.
2. Detect the host architecture.
3. Create the Kind Kubernetes cluster.
4. Connect the Kind control plane to the Docker Compose network.
5. Configure Kubernetes connectivity.
6. Pre-pull the GitHub Actions runner image.
7. Load the runner image into Kind.
8. Install the ARC controller.
9. Install the ARC runner scale set.
10. Wait for the minimum runner to become available.
11. Validate the installation.

When the environment is ready, the setup container remains running so the environment can be inspected during the demo.

## Verify Kubernetes

Open another terminal.

Check the Kind cluster:

```bash
docker exec demo-arc-setup kubectl get nodes
```

Expected:

```text
NAME                              STATUS   ROLES           AGE   VERSION
demo-arc-cluster-control-plane   Ready    control-plane   ...   v1.30.0
```

## Verify ARC

Check the ARC controller:

```bash
docker exec demo-arc-setup kubectl get pods -n arc-systems
```

You should see the ARC controller and listener running.

Then check the runner scale set:

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets \
  -n arc-runners
```

You should see something similar to:

```text
NAME             MINIMUM RUNNERS   MAXIMUM RUNNERS   CURRENT RUNNERS
arc-runner-set   1                 3                 1
```

Because `minRunners` is configured to `1`, a runner should normally be available even when there are no jobs running.

## Test the GitHub Actions Runner

The workflow must use the runner scale set name:

```yaml
runs-on: arc-runner-set
```

For example:

```yaml
name: ARC Runner Verification

on:
  workflow_dispatch:

jobs:
  verify-runner:
    runs-on: arc-runner-set

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Verify runner
        run: |
          echo "Running on an ARC-managed runner"
          echo "Runner: $(hostname)"
          echo "User: $(whoami)"
          uname -a
```

Go to:

```text
GitHub → Repository → Actions
```

Run the workflow manually.

Then watch the Kubernetes runners:

```bash
docker exec demo-arc-setup \
  kubectl get pods \
  -n arc-runners \
  -w
```

You should see the runner pod become available and execute the GitHub Actions job.

## Demonstrating Autoscaling

The repository includes a matrix-based workload that can create multiple jobs concurrently.

For example:

```yaml
strategy:
  matrix:
    worker: [1, 2, 3]

runs-on: arc-runner-set
```

Each matrix entry becomes a separate GitHub Actions job.

While the workflow is running:

```bash
docker exec demo-arc-setup \
  kubectl get pods \
  -n arc-runners \
  -w
```

You should see additional runner pods being created when the existing capacity is insufficient.

You can also inspect the scale set:

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets \
  -n arc-runners
```

Important fields include:

```text
MINIMUM RUNNERS
MAXIMUM RUNNERS
CURRENT RUNNERS
PENDING RUNNERS
RUNNING RUNNERS
FINISHED RUNNERS
```

For example, during concurrent workloads you may observe:

```text
NAME             MINIMUM RUNNERS   MAXIMUM RUNNERS   CURRENT RUNNERS
arc-runner-set   1                 3                 3
```

After the jobs finish, ephemeral runners should be removed and capacity should return toward the configured minimum.

## Autoscaling Flow

```text
GitHub Actions jobs increase
        │
        ▼
Pending jobs detected
        │
        ▼
ARC requests additional runners
        │
        ▼
Kubernetes creates runner pods
        │
        ▼
Runner pods connect to GitHub
        │
        ▼
Jobs execute
        │
        ▼
Jobs finish
        │
        ▼
Ephemeral runner pods are removed
        │
        ▼
Runner capacity returns toward minRunners
```

## Useful Commands

### List all Kubernetes pods

```bash
docker exec demo-arc-setup \
  kubectl get pods -A
```

### Watch runner pods

```bash
docker exec demo-arc-setup \
  kubectl get pods \
  -n arc-runners \
  -w
```

### Check ARC controller logs

```bash
docker exec demo-arc-setup \
  kubectl logs \
  -n arc-systems \
  deployment/arc-controller-gha-rs-controller
```

### Check runner scale set

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets \
  -n arc-runners
```

### Describe the runner scale set

```bash
docker exec demo-arc-setup \
  kubectl describe autoscalingrunnerset \
  arc-runner-set \
  -n arc-runners
```

### Check Kubernetes nodes

```bash
docker exec demo-arc-setup \
  kubectl get nodes
```

## Cleanup

To completely remove the local ARC demo environment:

```bash
./destroy.sh
```

This removes the Kind cluster and stops the Docker Compose environment.

## Portability

The setup detects the host architecture automatically.

Supported architectures:

```text
x86_64       → amd64
aarch64      → arm64
```

The appropriate Kind binary is downloaded dynamically:

```text
kind-linux-amd64
kind-linux-arm64
```

The runner image is also pre-pulled and loaded into the Kind node during setup to avoid waiting for Kubernetes/containerd to download the image when a runner is first created.

This allows the same project to be used on common Intel/AMD and Apple Silicon environments, assuming Docker is available.

## Why Kind?

Kind provides a lightweight Kubernetes environment designed to run Kubernetes nodes as Docker containers.

That makes it useful for this demo because:

* No cloud account is required.
* No managed Kubernetes cluster is required.
* The entire environment runs locally.
* Kubernetes behavior can be observed directly.
* The environment can be destroyed and recreated.
* ARC can be demonstrated using real Kubernetes resources.

## Why ARC?

GitHub Actions Runner Scale Sets allow GitHub Actions workloads to use dynamically provisioned self-hosted runners.

Instead of maintaining a fixed pool of runner machines:

```text
Traditional self-hosted runners

GitHub
  │
  ├── Runner 1
  ├── Runner 2
  ├── Runner 3
  └── Runner 4

Always running
```

ARC enables an elastic model:

```text
GitHub
  │
  ▼
ARC
  │
  ├── Runner Pod
  ├── Runner Pod
  └── Runner Pod

Created when needed
Removed when finished
```

This is useful when runner workloads need to scale dynamically while avoiding permanently running runner infrastructure.

## Troubleshooting

### `GITHUB_PAT is not set`

Set the environment variable before starting Compose:

```bash
export GITHUB_PAT="your_github_token"
export GITHUB_CONFIG_URL="https://github.com/OWNER/REPOSITORY"

docker compose up
```

### `GITHUB_CONFIG_URL is not set`

Set the repository URL:

```bash
export GITHUB_CONFIG_URL="https://github.com/OWNER/REPOSITORY"
```

The URL must point to the GitHub repository where the runner scale set should be registered.

### Runner scale set shows zero runners

With the current configuration:

```yaml
minRunners: 1
```

the scale set should normally maintain one runner.

If no runner exists, check:

```bash
docker exec demo-arc-setup \
  kubectl get pods \
  -n arc-runners
```

Then inspect the scale set:

```bash
docker exec demo-arc-setup \
  kubectl describe autoscalingrunnerset \
  arc-runner-set \
  -n arc-runners
```

### Workflow stays queued

Verify the following:

1. The workflow uses:

```yaml
runs-on: arc-runner-set
```

2. The ARC listener is running:

```bash
docker exec demo-arc-setup \
  kubectl get pods \
  -n arc-systems
```

3. The runner scale set exists:

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets \
  -n arc-runners
```

4. `GITHUB_CONFIG_URL` points to the repository containing the workflow.

5. The GitHub PAT has the required permissions.

### Kubernetes API connectivity problems

Verify that the Kind control plane is connected to the Compose network:

```bash
docker inspect demo-arc-cluster-control-plane \
  --format '{{json .NetworkSettings.Networks}}'
```

The output should contain:

```text
arc-runners-demo-network
```

You can also test the Kubernetes API from the Compose network:

```bash
docker run --rm \
  --network arc-runners-demo-network \
  alpine:3.19 \
  sh -c '
    apk add --no-cache curl >/dev/null &&
    curl -sk https://demo-arc-cluster-control-plane:6443/version
  '
```

A successful response should contain Kubernetes version information.

## Proof of Concept Scope

This project is intentionally a local **Proof of Concept** rather than a production-ready Kubernetes platform.

The objective is to demonstrate the core integration:

```text
GitHub Actions
      │
      ▼
GitHub ARC
      │
      ▼
Kubernetes
      │
      ▼
Ephemeral Runners
      │
      ▼
Elastic CI/CD Capacity
```

A production implementation would use a managed Kubernetes platform such as **Amazon EKS**, with dedicated compute capacity, production networking, security controls, secrets management, observability, autoscaling policies, and appropriate isolation.

The same architectural pattern can therefore be extended from this local Kind environment to cloud infrastructure.

## Goal of the Demo

The purpose of this project is to demonstrate a practical platform-engineering pattern:

> **GitHub Actions workloads can dynamically consume Kubernetes-based ephemeral compute through Actions Runner Controller.**

The local implementation provides a reproducible environment for experimenting with that architecture before moving toward a production implementation.
