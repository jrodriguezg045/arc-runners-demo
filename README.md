# GitHub Actions Runner Scale Set Demo

A portable local demo of **GitHub Actions Runner Scale Sets (ARC)** running on a local **Kubernetes cluster managed by Kind**.

The project uses Docker Compose to bootstrap the environment, making it possible to reproduce the demo on different machines and CPU architectures without requiring a pre-existing Kubernetes cluster.

The demo uses **one pre-provisioned runner** and can automatically scale up to **three concurrent runners** when additional GitHub Actions jobs are queued.

---

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
│  │  │ Kubernetes API                  │  │  │
│  │  │ ARC Controller                  │  │  │
│  │  │ Runner Scale Set                │  │  │
│  │  │ Runner Pods                     │  │  │
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

The `demo-arc-setup` container is responsible for creating and configuring the local Kubernetes environment. The Kind control-plane container runs the Kubernetes node and its container runtime.

---

## What This Demo Shows

The demo validates that:

* A Kubernetes cluster can be created automatically with Kind.
* ARC can be installed without an existing Kubernetes environment.
* GitHub Actions can dynamically request self-hosted runners.
* A minimum runner capacity can be kept available using `minRunners`.
* ARC can scale runner capacity based on pending GitHub Actions jobs.
* Runner pods are ephemeral and are removed after jobs complete.
* The environment can be reproduced using Docker Compose.
* The setup works on both `amd64` and `arm64` hosts.
* The GitHub Actions runner image can be preloaded into the local Kind node to avoid pulling it when a runner starts.

---

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

---

## GitHub Token

The runner scale set needs a GitHub token to authenticate with GitHub.

Export your token before starting the demo:

```bash
export GITHUB_PAT="your_github_token"
```

The token must have the permissions required by GitHub Actions Runner Scale Sets for the repository being used.

**Do not commit the token to the repository.**

---

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
├── setup.sh
├── destroy.sh
└── README.md
```

---

## Configuration

The main ARC configuration is located at:

```text
kubernetes/runner-values.yaml
```

The current configuration is:

```yaml
githubConfigUrl: "https://github.com/OWNER/REPOSITORY"

runnerScaleSetName: "arc-runner-set"

minRunners: 1
maxRunners: 3

template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/actions/actions-runner:latest
        imagePullPolicy: IfNotPresent

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

> Update `githubConfigUrl` to point to the GitHub repository that will run the demo.

---

## Runner Scaling

The demo uses:

```yaml
minRunners: 1
maxRunners: 3
```

This means:

* At least one runner is maintained by the scale set.
* The runner is available before a GitHub Actions job is submitted.
* ARC can create additional runners when multiple jobs are queued.
* The scale set supports up to three concurrent runners.
* Ephemeral runner pods are removed after completing their jobs.

The expected behavior is:

```text
No jobs
   │
   ▼
1 runner
   │
   │ additional jobs queued
   ▼
2 runners
   │
   │ additional jobs queued
   ▼
3 runners
   │
   │ jobs finish
   ▼
1 runner
```

Because `minRunners` is `1`, the demo intentionally keeps one runner available instead of scaling down to zero.

This allows a GitHub Actions job to start without first waiting for ARC to provision the initial runner.

---

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
6. Wait for the Kubernetes node to become ready.
7. Pull the GitHub Actions runner image.
8. Load the runner image into the Kind node.
9. Install the ARC controller.
10. Install the ARC Runner Scale Set.
11. Wait for the minimum runner to be created.
12. Wait for the runner pod to become ready.
13. Validate the installation.

The first startup may take some time because the environment needs to create the Kubernetes cluster, download the runner image, load the image into Kind, install ARC, and wait for the runner to become ready.

Once the environment is ready, the setup container remains running so the Kubernetes environment can be inspected from another terminal.

---

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

---

## Verify ARC

Check the ARC components:

```bash
docker exec demo-arc-setup kubectl get pods -n arc-systems
```

You should see the ARC controller and listener running.

Then check the Runner Scale Set:

```bash
docker exec demo-arc-setup kubectl get autoscalingrunnersets -n arc-runners
```

Expected:

```text
NAME             MINIMUM RUNNERS   MAXIMUM RUNNERS   CURRENT RUNNERS
arc-runner-set   1                 3                 1
```

The exact output may also contain additional columns such as:

```text
STATE
PENDING RUNNERS
RUNNING RUNNERS
FINISHED RUNNERS
DELETING RUNNERS
```

With `minRunners: 1`, the scale set should normally maintain one runner when there are no GitHub Actions jobs.

---

## Verify the Runner

Check the runner pods:

```bash
docker exec demo-arc-setup kubectl get pods -n arc-runners
```

Expected:

```text
NAME                                READY   STATUS    RESTARTS   AGE
arc-runner-set-xxxxx-runner-xxxxx   1/1     Running   0          ...
```

The runner image is preloaded into the Kind node during setup. The runner uses:

```yaml
imagePullPolicy: IfNotPresent
```

so Kubernetes can use the locally available image instead of downloading it again when creating the runner.

---

## Test the GitHub Actions Runner

The workflow must use the ARC Runner Scale Set name:

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

Because `minRunners` is set to `1`, a runner should already be available.

You can observe the runner:

```bash
docker exec demo-arc-setup kubectl get pods -n arc-runners -w
```

---

## Demonstrating Autoscaling

The repository includes a matrix-based workload that creates multiple jobs concurrently.

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
docker exec demo-arc-setup kubectl get pods -n arc-runners -w
```

You should see ARC create additional runner pods as jobs are queued.

You can also inspect the scale set:

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets \
  -n arc-runners
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

For example, during the workload you may see:

```text
NAME             MINIMUM RUNNERS   MAXIMUM RUNNERS   CURRENT RUNNERS
arc-runner-set   1                 3                 3
```

After the jobs finish, the scale set should return toward its minimum capacity:

```text
CURRENT RUNNERS
1
```

This demonstrates the core ARC behavior:

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
Jobs execute
        │
        ▼
Jobs finish
        │
        ▼
Ephemeral runners are removed
        │
        ▼
Runner capacity returns toward minimum
```

---

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
  kubectl logs \
  -n arc-systems \
  deployment/arc-controller-gha-rs-controller
```

### Check Runner Scale Set

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets \
  -n arc-runners
```

### Describe the Runner Scale Set

```bash
docker exec demo-arc-setup \
  kubectl describe autoscalingrunnerset \
  arc-runner-set \
  -n arc-runners
```

### Check Kubernetes nodes

```bash
docker exec demo-arc-setup kubectl get nodes
```

### Check runner image on the Kind node

```bash
docker exec demo-arc-cluster-control-plane \
  crictl images | grep actions-runner
```

---

## Cleanup

To completely remove the local ARC demo environment, run:

```bash
./destroy.sh
```

The cleanup script removes the Kind cluster and stops the Docker Compose environment.

If Docker Desktop reports a filesystem/storage error while removing containers, restart Docker Desktop and run the cleanup command again.

---

## Portability

The setup detects the host architecture automatically.

Supported architectures:

```text
x86_64  → amd64
aarch64 → arm64
```

The appropriate Kind binary is downloaded dynamically:

```text
kind-linux-amd64
kind-linux-arm64
```

This allows the same project to be used on common Intel/AMD and Apple Silicon environments, assuming Docker is available.

---

## Why Kind?

Kind provides a lightweight Kubernetes environment designed to run Kubernetes nodes as Docker containers.

That makes it useful for this demo because:

* No cloud account is required.
* No managed Kubernetes cluster is required.
* The entire environment runs locally.
* Kubernetes behavior can be observed directly.
* The setup can be destroyed and recreated quickly.
* ARC can be demonstrated using real Kubernetes resources.

---

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

Created as capacity is needed
Removed after jobs complete
```

In this demo, one runner is kept available while additional runners are created when concurrent workload increases.

This model is particularly useful when runner workloads need to scale dynamically without maintaining a permanently large runner fleet.

---

## Troubleshooting

### `GITHUB_PAT is not set`

Set the environment variable before starting Compose:

```bash
export GITHUB_PAT="your_github_token"

docker compose up
```

---

### Runner Scale Set shows one runner

This is expected with the current configuration:

```yaml
minRunners: 1
```

The demo intentionally keeps one runner available when there are no jobs.

---

### Runner scale set does not scale

Verify that the workflow uses:

```yaml
runs-on: arc-runner-set
```

Check the ARC components:

```bash
docker exec demo-arc-setup \
  kubectl get pods \
  -n arc-systems
```

Check the Runner Scale Set:

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets \
  -n arc-runners
```

Check the runner pods:

```bash
docker exec demo-arc-setup \
  kubectl get pods \
  -n arc-runners
```

---

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

3. The Runner Scale Set exists:

```bash
docker exec demo-arc-setup \
  kubectl get autoscalingrunnersets \
  -n arc-runners
```

4. The GitHub configuration URL in `runner-values.yaml` points to the correct repository.

5. The GitHub token has the required permissions.

---

### Runner image takes a long time to load

During the initial setup, the runner image is:

1. Pulled from GHCR.
2. Loaded into the Kind node.
3. Used by Kubernetes when ARC creates runner pods.

You may see:

```text
Pulling runner image...
Loading runner image into Kind...
```

This is expected during the initial setup.

You can verify that the image exists inside the Kind node:

```bash
docker exec demo-arc-cluster-control-plane \
  crictl images | grep actions-runner
```

---

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

---

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

The local Kind environment provides a lightweight way to demonstrate the architecture without requiring cloud infrastructure.

The same architectural pattern can later be extended to a cloud Kubernetes environment such as Amazon EKS, where runner pods can scale across actual compute capacity.
