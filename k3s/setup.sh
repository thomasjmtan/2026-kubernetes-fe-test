#!/usr/bin/env bash
# One-time setup (and config changes): headlamp, staging and prod environments.
# Safe to re-run: never changes the image a running environment uses.
# Usage: ./setup.sh
set -euo pipefail
. "$(dirname "$0")/lib.sh"

if ! docker exec k3s ctr images ls -q | grep -q 'kanso-web:1.0.0$'; then
  import_image 1.0.0
fi

echo "==> Applying headlamp"
kc apply -f /manifests/headlamp.yaml

for env in staging prod; do
  ns="$(env_ns "${env}")"
  image="kanso-web:1.0.0"
  if kc -n "${ns}" get deploy/kanso-web >/dev/null 2>&1; then
    image="$(current_image "${ns}")"
  fi
  echo "==> Applying ${env} (${image})"
  kc kustomize "/manifests/kanso/${env}" \
    | sed "s#image: kanso-web:1.0.0#image: ${image}#" \
    | kc apply -f -
done

echo "==> Removing old kanso namespace"
kc delete namespace kanso --ignore-not-found

for env in staging prod; do
  kc -n "$(env_ns "${env}")" rollout status deploy/kanso-web --timeout=120s
done
