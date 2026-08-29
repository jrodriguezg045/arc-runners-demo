#!/bin/sh
set -eu

CLUSTER_NAME="demo-arc-cluster"
KIND_CONTEXT="kind-${CLUSTER_NAME}"
CONTROL_PLANE="${CLUSTER_NAME}-control-plane"
DOCKER_NETWORK="${DOCKER_NETWORK:-arc-runners-demo-network}"

# GitHub Actions runner image
RUNNER_IMAGE="ghcr.io/actions/actions-runner:latest"

echo "============================================"
echo "ARC Demo Environment Setup"
echo "============================================"
echo ""

# ============================================================
# Detect architecture
# ============================================================

ARCH="$(uname -m)"

case "$ARCH" in
  x86_64)
    PLATFORM="amd64"
    ;;
  aarch64|arm64)
    PLATFORM="arm64"
    ;;
  *)
    echo "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

echo "Detected architecture: $ARCH"
echo "Using Linux platform: $PLATFORM"
echo ""

# ============================================================
# [1/4] Install required tools
# ============================================================

echo "[1/4] Installing required tools..."

apk add --no-cache \
  docker \
  helm \
  kubectl \
  curl \
  bash \
  ca-certificates

# ============================================================
# Install Kind
# ============================================================

if ! command -v kind >/dev/null 2>&1; then
  echo "Installing Kind v0.23.0..."

  KIND_VERSION="v0.23.0"
  KIND_URL="https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${PLATFORM}"

  curl -fL "$KIND_URL" -o /usr/local/bin/kind
  chmod +x /usr/local/bin/kind

  kind version
else
  echo "Kind is already installed:"
  kind version
fi

# ============================================================
# Verify required tools
# ============================================================

echo ""
echo "Verifying required tools..."

command -v docker
command -v kind
command -v kubectl
command -v helm

echo "Required tools are available."

# ============================================================
# [2/4] Create / verify Kind cluster
# ============================================================

echo ""
echo "[2/4] Creating/verifying Kubernetes cluster..."

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster $CLUSTER_NAME already exists."
else
  echo "Creating cluster $CLUSTER_NAME..."
  kind create cluster --name "$CLUSTER_NAME"
fi

# ============================================================
# Connect control-plane to the Compose network
# ============================================================

echo ""
echo "Checking control-plane network..."

if ! docker inspect "$CONTROL_PLANE" >/dev/null 2>&1; then
  echo "Kind control-plane container not found:"
  echo "  $CONTROL_PLANE"
  exit 1
fi

if docker inspect "$CONTROL_PLANE" \
    --format '{{json .NetworkSettings.Networks}}' |
    grep -q "\"${DOCKER_NETWORK}\""; then

  echo "Control-plane is already connected to ${DOCKER_NETWORK}."

else

  echo "Connecting control-plane to ${DOCKER_NETWORK}..."

  docker network connect "$DOCKER_NETWORK" "$CONTROL_PLANE"

  echo "Control-plane connected to ${DOCKER_NETWORK}."

fi

# ============================================================
# Verify Docker DNS / network connectivity
# ============================================================

echo ""
echo "Verifying Kubernetes API network connectivity..."

if ! docker run --rm \
    --network "$DOCKER_NETWORK" \
    alpine:3.19 \
    sh -c "apk add --no-cache curl >/dev/null 2>&1 && curl -sk --fail https://${CONTROL_PLANE}:6443/version >/dev/null"; then

  echo "Could not reach Kubernetes API through Docker DNS."
  echo ""
  echo "Control-plane network:"
  docker inspect "$CONTROL_PLANE" \
    --format '{{json .NetworkSettings.Networks}}'

  exit 1
fi

echo "Kubernetes API is reachable through Docker network."

# ============================================================
# Generate kubeconfig
# ============================================================

echo ""
echo "Generating Kind kubeconfig..."

mkdir -p /root/.kube

kind export kubeconfig \
  --name "$CLUSTER_NAME" \
  --kubeconfig /root/.kube/config

export KUBECONFIG=/root/.kube/config

kubectl config use-context "$KIND_CONTEXT"

# ============================================================
# Configure Kubernetes API endpoint
# ============================================================

echo ""
echo "Configuring Kubernetes API endpoint..."

# Use the Docker DNS name instead of the dynamic container IP.
# The Kind API server certificate contains this DNS name as a SAN.

kubectl config set-cluster "$KIND_CONTEXT" \
  --server="https://${CONTROL_PLANE}:6443"

kubectl config use-context "$KIND_CONTEXT"

echo "Kubernetes API endpoint:"
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
echo ""

# ============================================================
# Wait for Kubernetes
# ============================================================

echo ""
echo "Waiting for Kubernetes..."

KUBE_READY=false

for i in $(seq 1 30); do
  if kubectl get nodes >/dev/null 2>&1; then
    KUBE_READY=true
    break
  fi

  echo "Kubernetes is not ready yet... attempt ${i}/30"
  sleep 2
done

if [ "$KUBE_READY" != "true" ]; then
  echo "Could not connect to Kubernetes."
  echo ""

  echo "Kubernetes API endpoint:"
  kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' || true
  echo ""

  echo "Control-plane network:"
  docker inspect "$CONTROL_PLANE" \
    --format '{{json .NetworkSettings.Networks}}'

  exit 1
fi

echo "Kubernetes is available."

kubectl get nodes

# ============================================================
# Wait for Kind node to become Ready
# ============================================================

echo ""
echo "Waiting for Kind control-plane node to become Ready..."

for i in $(seq 1 30); do
  if kubectl wait \
      --for=condition=Ready \
      node/"$CONTROL_PLANE" \
      --timeout=5s >/dev/null 2>&1; then

    echo "Kind control-plane node is Ready."
    break
  fi

  echo "Node is not ready yet... attempt ${i}/30"
  sleep 2
done

# ============================================================
# Pre-load GitHub Actions runner image into Kind
# ============================================================

echo ""
echo "Pre-loading GitHub Actions runner image..."
echo "Image: ${RUNNER_IMAGE}"

echo "Pulling runner image into Docker..."

docker pull "$RUNNER_IMAGE"

echo "Loading runner image into Kind..."

kind load docker-image "$RUNNER_IMAGE" \
  --name "$CLUSTER_NAME"

echo "Runner image is available in Kind."

# ============================================================
# [3/4] Install Actions Runner Controller
# ============================================================

echo ""
echo "[3/4] Installing Actions Runner Controller..."

helm repo add actions-runner-controller \
  https://actions-runner-controller.github.io/actions-runner-controller \
  --force-update

helm repo update

helm upgrade --install arc-controller \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --namespace arc-systems \
  --create-namespace

echo "ARC Controller installed."

# ============================================================
# [4/4] Install Runner Scale Set
# ============================================================

echo ""
echo "[4/4] Deploying Runner Scale Set..."

if [ -z "${GITHUB_PAT:-}" ]; then
  echo "GITHUB_PAT is not set."
  echo ""
  echo "Set it before running Docker Compose:"
  echo "  export GITHUB_PAT=your_token"
  echo ""
  exit 1
fi

helm upgrade --install arc-runner-set \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --namespace arc-runners \
  --create-namespace \
  --values kubernetes/runner-values.yaml \
  --set githubConfigSecret.github_token="$GITHUB_PAT"

echo "Runner Scale Set installed."

# ============================================================
# Wait for minimum runner
# ============================================================

echo ""
echo "Waiting for minimum runner to be created..."

RUNNER_READY=false

for i in $(seq 1 60); do

  RUNNER_POD="$(kubectl get pods \
    -n arc-runners \
    -l app.kubernetes.io/component=runner \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

  if [ -n "$RUNNER_POD" ]; then
    echo "Runner pod created: ${RUNNER_POD}"
    break
  fi

  echo "Runner pod not created yet... attempt ${i}/60"
  sleep 2

done

if [ -z "${RUNNER_POD:-}" ]; then

  echo "Runner pod was not created within the timeout."
  echo ""

  echo "Runner Scale Set:"
  kubectl get autoscalingrunnersets -n arc-runners

  echo ""
  echo "ARC system pods:"
  kubectl get pods -n arc-systems

  echo ""
  echo "ARC events:"
  kubectl get events \
    -n arc-systems \
    --sort-by=.lastTimestamp

  echo ""
  echo "Runner namespace events:"
  kubectl get events \
    -n arc-runners \
    --sort-by=.lastTimestamp

  exit 1

fi

# ============================================================
# Wait for runner pod to become Ready
# ============================================================

echo ""
echo "Waiting for runner pod to become Ready..."

if kubectl wait \
    --for=condition=Ready \
    "pod/${RUNNER_POD}" \
    -n arc-runners \
    --timeout=180s; then

  RUNNER_READY=true
  echo "Runner is ready."

else

  echo "Runner did not become ready within the timeout."
  echo ""

  echo "Runner pod:"
  kubectl get pod \
    "${RUNNER_POD}" \
    -n arc-runners \
    -o wide

  echo ""
  echo "Runner pod details:"
  kubectl describe pod \
    "${RUNNER_POD}" \
    -n arc-runners

  exit 1

fi

# ============================================================
# Validation
# ============================================================

echo ""
echo "Validating ARC installation..."

echo ""
echo "ARC controller pods:"
kubectl get pods -n arc-systems

echo ""
echo "ARC runner resources:"
kubectl get autoscalingrunnersets -n arc-runners

echo ""
echo "============================================"
echo "ARC environment is ready"
echo "============================================"
echo ""

echo "Kubernetes:"
kubectl get nodes

echo ""
echo "ARC:"
kubectl get pods -A

echo ""
echo "Runner Scale Set:"
kubectl get autoscalingrunnersets -n arc-runners

echo ""
echo "Ready runner:"
kubectl get pods \
  -n arc-runners \
  -l app.kubernetes.io/component=runner

echo ""
echo "The setup container will remain alive for the demo."

tail -f /dev/null
