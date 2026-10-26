#!/usr/bin/env bash
# Build the frontend image, load it into k3s, and roll the Deployment to it.
# Usage: ./deploy.sh [tag]   (default tag: 1.0.0)
set -euo pipefail

TAG="${1:-1.0.0}"
IMAGE="kanso-web:${TAG}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# MSYS_NO_PATHCONV: stop Git Bash on Windows rewriting container paths like /manifests
kc() { MSYS_NO_PATHCONV=1 docker exec k3s kubectl "$@"; }

echo "==> Building ${IMAGE}"
docker build -t "${IMAGE}" "${HERE}/../frontend"

echo "==> Importing ${IMAGE} into k3s"
docker save "${IMAGE}" | docker exec -i k3s ctr images import -

if ! kc -n kanso get deploy/kanso-web >/dev/null 2>&1; then
  echo "==> First deploy: applying manifests"
  kc apply -f /manifests/
fi

echo "==> Rolling kanso-web to ${IMAGE}"
kc -n kanso set image deploy/kanso-web web="${IMAGE}"
kc -n kanso annotate deploy/kanso-web kubernetes.io/change-cause="deploy ${IMAGE}" --overwrite
kc -n kanso rollout status deploy/kanso-web --timeout=120s
