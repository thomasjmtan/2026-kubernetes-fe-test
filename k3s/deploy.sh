#!/usr/bin/env bash
# Build the frontend image, load it into k3s, and roll STAGING to it.
# Usage: ./deploy.sh <tag>
set -euo pipefail
. "$(dirname "$0")/lib.sh"

if [ $# -lt 1 ] || [ -z "$1" ]; then
  echo "Usage: $(basename "$0") <tag>" >&2
  exit 2
fi
TAG="$1"
IMAGE="kanso-web:${TAG}"
NS="$(env_ns staging)"

if [ "$(current_image "${NS}")" = "${IMAGE}" ]; then
  echo "staging already runs ${IMAGE}; nothing to do"
  exit 0
fi

import_image "${TAG}"

echo "==> Rolling staging to ${IMAGE}"
kc -n "${NS}" set image deploy/kanso-web web="${IMAGE}"
kc -n "${NS}" annotate deploy/kanso-web kubernetes.io/change-cause="deploy ${IMAGE}" --overwrite
kc -n "${NS}" rollout status deploy/kanso-web --timeout=120s
