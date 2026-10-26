#!/usr/bin/env bash
# Shared helpers, sourced by setup.sh / deploy.sh / promote.sh / rollback.sh.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run kubectl. With KANSO_KUBECONFIG set, use host kubectl with that kubeconfig;
# otherwise exec inside the k3s container (-i so piped stdin works).
# MSYS_NO_PATHCONV: stop Git Bash on Windows rewriting container paths like /manifests
kc() {
  if [ -n "${KANSO_KUBECONFIG:-}" ]; then
    kubectl --kubeconfig "${KANSO_KUBECONFIG}" "$@"
  else
    MSYS_NO_PATHCONV=1 docker exec -i k3s kubectl "$@"
  fi
}

# import_image <tag>: build kanso-web:<tag> and load it into k3s
import_image() {
  local image="kanso-web:$1"
  echo "==> Building ${image}"
  docker build --build-arg "VERSION=$1" -t "${image}" "${HERE}/../frontend"
  echo "==> Importing ${image} into k3s"
  docker save "${image}" | docker exec -i k3s ctr images import -
}

# env_ns <staging|prod>: print the namespace for an environment
env_ns() {
  case "${1:-}" in
    staging) echo kanso-staging ;;
    prod) echo kanso-prod ;;
    *) echo "Usage: $(basename "$0") <staging|prod>" >&2; exit 2 ;;
  esac
}

# current_image <ns>: print the web container image of deploy/kanso-web
current_image() {
  kc -n "$1" get deploy/kanso-web \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="web")].image}'
}
