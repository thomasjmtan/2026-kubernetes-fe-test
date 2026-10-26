# Implementation plan: staging + production on local k3s (PLAN.md Phases 1 and 3)

Spec: `PLAN.md` (repo root), Phase 1 and Phase 3. Phases 2, 4, 5 need the user's GitHub
credentials and are out of scope here.

## Context

- Windows 11 workstation, Git Bash. Docker 29 + Compose v5. `kubectl` on PATH (Docker Desktop).
  No python. No `gh`. `openssl` is available in Git Bash.
- k3s runs as one Docker container named `k3s` (`k3s/docker-compose.yml`, image
  `rancher/k3s:v1.36.5-k3s1`). It is running now. Traefik ingress is published on host
  port **8081**, the API on **6443**. `./manifests` is mounted read-only at `/manifests` in
  the container. `docker compose up` writes an admin kubeconfig to
  `k3s/kubeconfig/kubeconfig.yaml` (git-ignored).
- Currently deployed: namespace `kanso` (Deployment/Service/Ingress `kanso-web`, host
  `kanso.localhost`) and namespace `headlamp` (`k3s/manifests/headlamp.yaml`, host
  `headlamp.localhost`).
- Test any host with: `curl -s -H "Host: <host>" http://127.0.0.1:8081/<path>`.
- **Git Bash gotcha:** Git Bash rewrites absolute Unix paths (e.g. `/manifests`) in
  arguments to Windows paths. Every `docker exec k3s ...` that passes a container path
  must be prefixed with `MSYS_NO_PATHCONV=1`. Do NOT export it globally (it breaks host
  paths like `docker build ../frontend`).

## Global Constraints

- k3s only. Push model: scripts/pipeline change the cluster; nothing in the cluster watches git (no GitOps tools).
- Promote = put the **exact image staging runs** on production. Never rebuild for production.
- Image name `kanso-web:<tag>`, loaded into k3s with `docker save | docker exec -i k3s ctr images import -`. `imagePullPolicy: IfNotPresent`.
- Namespaces: `kanso-staging` (host `staging.kanso.localhost`, 1 replica) and `kanso-prod` (host `kanso.localhost`, 2 replicas). The old `kanso` namespace is removed.
- Secrets (kubeconfigs, tokens, passwords) are never committed and never printed to stdout by scripts except the one place Task 4 specifies. They live in git-ignored `k3s/.secrets/`.
- Shell scripts: bash, `set -euo pipefail`, LF line endings (`.gitattributes` already forces `*.sh` to LF). Match the existing style of `k3s/deploy.sh` (short comments, `==>` progress lines).
- Keep it simple: no Helm, no extra tools. `kubectl apply -k` / `kubectl kustomize` (built into kubectl) is allowed.
- Commit when the task is done, one or more commits, message ending with:
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Never push.

---

## Task 1: Show the version on the page

Files: `frontend/Dockerfile`, `frontend/nginx.conf`, `frontend/index.html`, `frontend/main.js`, `frontend/docker-compose.yml`.

1. `frontend/Dockerfile`: add `ARG VERSION=dev` and write it to
   `/usr/share/nginx/html/version.txt` (one line, the version string).
2. `frontend/nginx.conf`: add `location = /version.txt` that serves the file with header
   `Cache-Control: no-store`.
3. `frontend/index.html`: in the footer, change `<p class="mono">© 2026 Kanso · 東京</p>` to also
   show the version, e.g. `© 2026 Kanso · 東京 · v<span id="version">…</span>`.
4. `frontend/main.js`: fetch `/version.txt` (`cache: "no-store"`), put the trimmed text in
   `#version`; on any failure show `dev`. Match the file's existing style (IIFE, short
   section comments).
5. `frontend/docker-compose.yml`: pass build arg `VERSION: ${KANSO_VERSION:-dev}`.

Verify:
- `docker build --build-arg VERSION=9.9.9 -t kanso-web:task1-test frontend`, run it on a free
  port (e.g. 18080), `curl /version.txt` → `9.9.9`, header includes `Cache-Control: no-store`,
  `curl /` still returns the page with `id="version"`. Remove the test container and image afterwards.

## Task 2: Kustomize base + staging/prod overlays

Replace `k3s/manifests/kanso.yaml` with:

```
k3s/manifests/kanso/base/kustomization.yaml     resources: deployment.yaml, service.yaml, ingress.yaml
k3s/manifests/kanso/base/deployment.yaml        (from kanso.yaml, no namespace field)
k3s/manifests/kanso/base/service.yaml
k3s/manifests/kanso/base/ingress.yaml           host kanso.localhost (overlays patch it)
k3s/manifests/kanso/staging/kustomization.yaml  namespace: kanso-staging; resources ../base + namespace.yaml; replicas 1; host staging.kanso.localhost
k3s/manifests/kanso/staging/namespace.yaml
k3s/manifests/kanso/prod/kustomization.yaml     namespace: kanso-prod; resources ../base + namespace.yaml; replicas 2; host kanso.localhost
k3s/manifests/kanso/prod/namespace.yaml
```

- Keep every field of the current Deployment/Service/Ingress (probes, resources, RollingUpdate
  maxSurge 1 / maxUnavailable 0, revisionHistoryLimit 5, ingressClassName traefik).
- Base image stays exactly `kanso-web:1.0.0` (Task 3's setup.sh relies on this string).
- Use the kustomize `replicas:` field and a JSON6902 or strategic-merge patch for the Ingress host.
- `k3s/manifests/headlamp.yaml` stays where it is, unchanged.

Verify (render only, do not apply yet; Task 3 applies):
- `MSYS_NO_PATHCONV=1 docker exec k3s kubectl kustomize /manifests/kanso/staging` and `.../prod`
  render without error, with the right namespace, replicas, host and image.
- Also `kubectl apply -k <overlay> --dry-run=server` via docker exec for both overlays succeeds.

## Task 3: Scripts: setup, deploy (staging), promote, rollback

Files: new `k3s/lib.sh`, new `k3s/setup.sh`, rewrite `k3s/deploy.sh`, new `k3s/promote.sh`,
new `k3s/rollback.sh`. All executable.

`k3s/lib.sh` (sourced by the others):
- `kc()` runs kubectl. If env `KANSO_KUBECONFIG` is set, use host `kubectl --kubeconfig "$KANSO_KUBECONFIG"`;
  otherwise `MSYS_NO_PATHCONV=1 docker exec k3s kubectl`. (Task 5's restricted account uses the first form.)
- `import_image <tag>`: build `kanso-web:<tag>` from `../frontend` with `--build-arg VERSION=<tag>`,
  then import into k3s.
- `env_ns <staging|prod>` → `kanso-staging|kanso-prod`; any other value: usage error, exit 2.
- `current_image <ns>`: print the `web` container image of `deploy/kanso-web`.

`k3s/setup.sh` — one-time setup and config changes; safe to re-run:
1. If `kanso-web:1.0.0` is not in k3s (`docker exec k3s ctr images ls -q`), `import_image 1.0.0`.
2. Apply `/manifests/headlamp.yaml`.
3. For each of staging and prod: if the Deployment exists, remember its current image; render the
   overlay with `kubectl kustomize`, replace `image: kanso-web:1.0.0` with the remembered image
   (so re-running setup never changes the running version), and `kubectl apply -f -`.
4. Delete the old `kanso` namespace if present (`--ignore-not-found`).
5. Wait for both rollouts (`rollout status --timeout=120s`).

`k3s/deploy.sh <tag>` — tag required (usage message + exit 2 if missing). Builds and imports
`kanso-web:<tag>`, sets it on **kanso-staging only**, sets annotation
`kubernetes.io/change-cause="deploy kanso-web:<tag>"`, waits for rollout. If staging already runs
that image, print that and exit 0 without changes. Never touches prod.

`k3s/promote.sh` — reads staging's current image and sets the same string on kanso-prod, change-cause
`"promote <image> from staging"`, waits for rollout. If prod already runs it, say so and exit 0.
Does not build or import anything.

`k3s/rollback.sh <staging|prod>` — `rollout undo`, wait for rollout, then print the image now running.

Verify end to end (cluster is running):
- `./setup.sh` → both namespaces up, old `kanso` gone; `curl -H "Host: kanso.localhost" .../version.txt` → `1.0.0`
  and same for `staging.kanso.localhost`.
- `./deploy.sh 1.1.0` → staging `/version.txt` = `1.1.0`, prod still `1.0.0`.
- `./promote.sh` → prod = `1.1.0`.
- `./rollback.sh prod` → prod = `1.0.0`, staging still `1.1.0`.
- Re-run `./setup.sh` → versions unchanged (staging 1.1.0, prod 1.0.0) and no new ReplicaSet revision
  is created on either Deployment.
- `./deploy.sh` with no tag → usage + exit 2; `./rollback.sh foo` → usage + exit 2.

## Task 4: Password on staging

- Traefik `Middleware` (`apiVersion: traefik.io/v1alpha1`, kind `Middleware`, name `staging-auth`)
  with `basicAuth.secret: staging-auth`, added to the **staging overlay only**, plus the Ingress
  annotation `traefik.ingress.kubernetes.io/router.middlewares: kanso-staging-staging-auth@kubernetescrd`
  in the staging overlay only.
- `setup.sh` creates Secret `staging-auth` in `kanso-staging` if it does not exist. Key `users`, one
  htpasswd line for user `staging`, hashed with `openssl passwd -apr1`. Password: env `STAGING_PASSWORD`
  if set, else a random 16-char alphanumeric one. Write the plain password to
  `k3s/.secrets/staging-password.txt` and print only the file path (not the password) to stdout.
  Never overwrite an existing Secret.
- Add `k3s/.secrets/` to `.gitignore`.
- The Secret must exist before the staging Ingress is applied (or Traefik rejects requests until it does — order it first).

Verify:
- `curl -H "Host: staging.kanso.localhost" .../` without credentials → 401.
- With `-u staging:<password from file>` → 200.
- Prod (`kanso.localhost`) → 200 with no credentials.
- Re-run `./setup.sh` → password file and Secret unchanged.
- Do not print the password in your report.

## Task 5: Restricted `deployer` account (PLAN.md Phase 3)

- `k3s/manifests/deployer.yaml`: Namespace `ci`; ServiceAccount `deployer` in `ci`; a Secret of type
  `kubernetes.io/service-account-token` for it (name `deployer-token`); in **each** of `kanso-staging`
  and `kanso-prod` a Role `deployer` + RoleBinding to `ci:deployer` allowing exactly what the scripts need:
  - `apps/deployments`: get, list, watch, patch, update
  - `apps/replicasets`: get, list, watch
  - `""/pods`: get, list, watch
- `setup.sh` applies it after the overlays.
- New `k3s/make-deployer-kubeconfig.sh`: writes `k3s/.secrets/deployer.kubeconfig` (server
  `https://127.0.0.1:6443`, the cluster CA, the token from `deployer-token`). Prints only the path.
  Never echoes the token.

Verify (with `KANSO_KUBECONFIG=k3s/.secrets/deployer.kubeconfig`):
- `kubectl --kubeconfig ... auth can-i patch deployments -n kanso-prod` → yes; same for kanso-staging.
- `auth can-i delete namespaces` → no; `auth can-i get pods -n kube-system` → no; `auth can-i get secrets -n kanso-prod` → no.
- `KANSO_KUBECONFIG=... ./promote.sh` and `KANSO_KUBECONFIG=... ./rollback.sh staging` work.
- `KANSO_KUBECONFIG=... ./deploy.sh <tag>` works too (build/import use docker directly; only the kubectl calls use the restricted account).

## Task 6: Docs

- Rewrite `k3s/README.md` for the new flow: URLs (prod, staging + where the password is, Headlamp),
  `docker compose up -d` → `./setup.sh` → `./deploy.sh <tag>` → `./promote.sh` → `./rollback.sh <env>`,
  the deployer account and `KANSO_KUBECONFIG`, Headlamp token, clean-up. Simple English, short.
- `PLAN.md`: mark Phase 1 and Phase 3 as done (a short "Status: done" line under each heading). No other changes.
