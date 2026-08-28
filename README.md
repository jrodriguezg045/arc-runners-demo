# GitHub Actions Runner Scale Set Demo

A portable local demo of **GitHub Actions Runner Scale Sets (ARC)** running on a local **Kubernetes cluster managed by Kind**.

The project uses Docker Compose to bootstrap the environment, making it possible to reproduce the demo on different machines and CPU architectures without requiring a pre-existing Kubernetes cluster.

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
│  │  │  Kubernetes API                 │  │  │
│  │  │  ARC Controller                 │  │  │
│  │  │  Runner Scale Set               │  │  │
│  │  │  Runner Pods                    │  │  │
│  │  └──────────────────────────────────┘  │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  ┌────────────────────────────────────────┐  │
│  │ demo-arc-setup                         │  │
│  │ Bootstrap container                    │  │
│  │                                        │  │
│  │ Docker CLI                             │  │
│  │ Kind                                    │  │
│  │ kubectl                                 │  │
│  │ Helm                                    │  │
│  └────────────────────────────────────────┘  │
│                                              │
└──────────────────────────────────────────────┘
```

## What This Demo Shows

The demo validates that:

* A Kubernetes cluster can be created automatically with Kind.
* ARC can be installed without an existing Kubernetes environment.
* GitHub Actions can dynamically request self-hosted runners.
* ARC creates runner pods on demand.
* Runner capacity can scale based on pending GitHub Actions jobs.
* Runner pods are removed after jobs complete.
* The entire environment can be reproduced with Docker Compose.
* The setup works on both `amd64` and `arm64` hosts.

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

### GitHub Token

The runner scale set needs a GitHub token to authenticate with GitHub.

Export your token before starting the demo:

```bash
export GITHUB_PAT="your_github_token"
```

The token should have the permissions required by GitHub Actions Runner Scale Sets for the repository being used.

Do not commit the token to the repository.

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
├── terraform/
│   └── ...
│
├── docker-compose.yml
├── entrypoint.sh
└── README.md
```

> The `terraform/` directory may exist in the repository for other experiments or future infrastructure work, but Terraform is **not required by the ARC demo bootstrap process**.

## Configuration

The main ARC configuration is located at:

```text
kubernetes/runner-values.yaml
```

Example:

```yaml
githubConfigUrl: "https://github.com/OWNER/REPOSITORY"

runnerScaleSetName: "arc-runner-set"

minRunners: 0
maxRunners: 5

template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        command:
          - /home/runner/run.sh
        resources:
          limits:
            cpu: "1"
            memory: "1Gi"
          requests:
            cpu: "0.5"
            memory: "512Mi"

containerMode:
  type: "kubernetes"
```

### Runner Scaling

The demo intentionally uses:

```yaml
minRunners: 0
maxRunners: 5
```

This means:

* No runner pods are kept alive when there is no work.
* ARC can create runners when jobs are queued.
* The demo can create up to five concurrent runners.

## Start the Demo

From the project directory:

```bash
export GITHUB_PAT="your_github_token"

docker compose up
```

The setup container will:

1. Install the required CLI tools.
2. Detect the host architecture.
3. Create the Kind Kubernetes cluster.
4. Connect the Kind control plane to the Docker Compose network.
5. Configure Kubernetes connectivity.
6. Install the ARC controller.
7. Install the ARC runner scale set.
8. Validate the installation.

When everything is ready, you should see:

```text
🎯 SUCCESS — ARC environment is ready
```

## Verify Kubernetes

Open another terminal.

Check the Kind cluster:

```bash
docker exec demo-arc-setup kubectl get nodes
```

Expected:

```text
NAME                         STATUS   ROLES           AGE
demo-arc-cluster-control-plane   Ready    control-plane   ...
```

## Verify ARC

Check the ARC controller:

```bash
docker exec demo-arc-setup kubectl get pods -n arc-systems
```

You should see the ARC controller and listener running.

Then check the runner scale set:

```bash
docker exec demo-arc-setup kubectl get autoscalingrunnersets -n arc-runners
```

Expected:

```text
NAME             MINIMUM RUNNERS   MAXIMUM RUNNERS   CURRENT RUNNERS
arc-runner-set   0                 5                 0
```

With no GitHub Actions jobs running, `CURRENT RUNNERS` should normally be `0`.

## Test the GitHub Actions Runner

The workflow must use the ARC runner scale set name:

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

Then watch the Kubernetes cluster:

```bash
docker exec demo-arc-setup kubectl get pods -n arc-runners -w
```

You should see ARC create a runner pod.

## Demonstrating Autoscaling

The repository includes a matrix-based workload that creates multiple jobs concurrently.

Example:

```yaml
strategy:
  matrix:
    worker: [1, 2, 3, 4]

runs-on: arc-runner-set
```

Each matrix entry becomes a separate GitHub Actions job.

While the workflow is running:

```bash
docker exec demo-arc-setup kubectl get pods -n arc-runners -w
```

You should see multiple runner pods being created.

You can also inspect the scale set:

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets -n arc-runners
```

The important fields are:

```text
MINIMUM RUNNERS
MAXIMUM RUNNERS
CURRENT RUNNERS
PENDING RUNNERS
RUNNING RUNNERS
FINISHED RUNNERS
```

For example, during the stress test you may see:

```text
NAME             MINIMUM RUNNERS   MAXIMUM RUNNERS   CURRENT RUNNERS
arc-runner-set   0                 5                 4
```

After the jobs finish, the runners should scale back down toward:

```text
CURRENT RUNNERS
0
```

This demonstrates the core ARC behavior:

```text
GitHub Actions jobs increase
        │
        ▼
Pending jobs detected
        │
        ▼
ARC requests runners
        │
        ▼
Kubernetes creates runner pods
        │
        ▼
Jobs execute
        │
        ▼
Jobs finish
        │
        ▼
Runner pods are removed
        │
        ▼
Runner capacity returns toward zero
```

## Useful Commands

### List all Kubernetes pods

```bash
docker exec demo-arc-setup kubectl get pods -A
```

### Watch runner pods

```bash
docker exec demo-arc-setup kubectl get pods -n arc-runners -w
```

### Check ARC controller logs

```bash
docker exec demo-arc-setup \
  kubectl logs -n arc-systems \
  deployment/arc-controller-gha-rs-controller
```

### Check runner scale set

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets -n arc-runners
```

### Describe the runner scale set

```bash
docker exec demo-arc-setup \
  kubectl describe autoscalingrunnerset arc-runner-set \
  -n arc-runners
```

### Check Kubernetes nodes

```bash
docker exec demo-arc-setup kubectl get nodes
```

## Cleanup

To completely remove the local ARC demo environment, run:

```bash
./destroy.sh

## Portability

The setup detects the host architecture automatically.

Supported architectures:

```text
x86_64 → amd64
aarch64 → arm64
```

The appropriate Kind binary is downloaded dynamically:

```text
kind-linux-amd64
kind-linux-arm64
```

This allows the same project to be used on common Intel/AMD and Apple Silicon environments, assuming Docker is available.

## Why Kind?

Kind provides a lightweight Kubernetes environment designed to run Kubernetes nodes as Docker containers.

That makes it useful for this demo because:

* No cloud account is required.
* No managed Kubernetes cluster is required.
* The entire environment runs locally.
* Kubernetes behavior can be observed directly.
* The setup can be destroyed and recreated quickly.
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

This is particularly useful when runner workloads need to scale dynamically while avoiding permanently running runner infrastructure.

## Troubleshooting

### `GITHUB_PAT is not set`

Set the environment variable before starting Compose:

```bash
export GITHUB_PAT="your_github_token"
docker compose up
```

### Runner scale set shows zero runners

This is expected when there are no queued GitHub Actions jobs:

```text
CURRENT RUNNERS: 0
```

Trigger the workflow using:

```yaml
runs-on: arc-runner-set
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
  kubectl get pods -n arc-systems
```

3. The runner scale set exists:

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets -n arc-runners
```

4. The GitHub configuration URL in `runner-values.yaml` points to the correct repository.

### Kubernetes API connectivity problems

Verify that the Kind control-plane is connected to the Compose network:

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

## Goal of the Demo

The purpose of this project is not to provide a production Kubernetes environment.

It is a reproducible local demonstration of the following platform-engineering pattern:

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

The same architectural pattern can later be extended to a cloud Kubernetes environment such as Amazon EKS, where runner pods can scale across actual compute capacity.

```
```