# k3s: local single-node cluster in Docker

k3s runs as one Docker container that is both the control plane and the worker.
Traefik (bundled with k3s) routes traffic on host port 8081.

| URL | What |
|---|---|
| http://kanso.localhost:8081 | Kanso frontend (2 replicas) |
| http://headlamp.localhost:8081 | Headlamp cluster UI |

## Start and deploy

```bash
cd k3s
docker compose up -d        # start the cluster (first start takes ~1 min)
./deploy.sh                 # build ../frontend, import into k3s, deploy kanso-web:1.0.0
```

## Rolling update and rollback

Each change needs a new tag; redeploying the same tag does not roll.

```bash
./deploy.sh 1.0.1
docker exec k3s kubectl -n kanso rollout history deploy/kanso-web
docker exec k3s kubectl -n kanso rollout undo deploy/kanso-web
```

## Headlamp login token

```bash
docker exec k3s kubectl -n headlamp create token headlamp-admin
```

The token grants cluster-admin. It is for this local trial only.

## kubectl from Windows

`docker compose up` writes `kubeconfig/kubeconfig.yaml` (git-ignored; it is a secret).

```bash
export KUBECONFIG="$PWD/kubeconfig/kubeconfig.yaml"
kubectl get pods -A
```

## Stop and clean up

```bash
docker compose down         # stop; cluster state is kept in the k3s-data volume
docker compose down -v      # stop and wipe the cluster
```
