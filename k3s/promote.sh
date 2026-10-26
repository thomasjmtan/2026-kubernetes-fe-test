#!/usr/bin/env bash
# Put the exact image staging runs on production. Does not build anything.
# Usage: ./promote.sh
set -euo pipefail
. "$(dirname "$0")/lib.sh"

STAGING="$(env_ns staging)"
PROD="$(env_ns prod)"
IMAGE="$(current_image "${STAGING}")"

if [ "$(current_image "${PROD}")" = "${IMAGE}" ]; then
  echo "prod already runs ${IMAGE}; nothing to do"
  exit 0
fi

echo "==> Promoting ${IMAGE} from staging to prod"
kc -n "${PROD}" set image deploy/kanso-web web="${IMAGE}"
kc -n "${PROD}" annotate deploy/kanso-web kubernetes.io/change-cause="promote ${IMAGE} from staging" --overwrite
kc -n "${PROD}" rollout status deploy/kanso-web --timeout=120s
