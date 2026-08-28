#!/bin/bash

set -e

CLUSTER_NAME="demo-arc-cluster"
CONTROL_PLANE="${CLUSTER_NAME}-control-plane"

echo "============================================"
echo "       ARC Demo Environment Cleanup.        "
echo "============================================"
echo ""

# ============================================================
# [1/3] Remove the Kind Kubernetes cluster
# ============================================================

echo "[1/3] Removing Kind Kubernetes cluster..."

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTROL_PLANE"; then

  echo "Removing Kind cluster: $CLUSTER_NAME"

  docker exec demo-arc-setup \
    kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true

  # The Kind control-plane container may still exist if the
  # setup container was stopped before Kind could remove it.

  docker rm -f "$CONTROL_PLANE" 2>/dev/null || true

else

  echo "Kind cluster does not exist."

fi

# ============================================================
# [2/3] Stop Docker Compose environment
# ============================================================

echo ""
echo "[2/3] Stopping Docker Compose environment..."

docker compose down --remove-orphans -v

echo "Docker Compose environment removed."

# ============================================================
# [3/3] Remove leftover Kind resources
# ============================================================

echo ""
echo "[3/3] Checking for leftover resources..."

# Remove the Kind Docker network if it still exists.
docker network rm kind 2>/dev/null || true

# Remove the demo network if it was left behind.
docker network rm arc-runners-demo-network 2>/dev/null || true

# Remove any orphaned control-plane container.
docker rm -f "$CONTROL_PLANE" 2>/dev/null || true

echo ""
echo "============================================"
echo "            Cleanup complete                "
echo "============================================"
echo ""
echo "The ARC demo environment has been removed."
echo ""