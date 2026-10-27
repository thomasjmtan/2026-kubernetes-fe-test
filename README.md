# Kanso on k3s

A small test bubble: the Kanso website (`frontend/`) running on a single-node k3s
cluster inside Docker (`k3s/`), with staging and production side by side.

## URLs

Start the cluster first: `cd k3s && docker compose up -d && ./setup.sh`

| What | URL | Notes |
|---|---|---|
| Kanso, production | http://kanso.localhost:8081 | 2 copies. Updated only by `./promote.sh`. |
| Kanso, staging | http://staging.kanso.localhost:8081 | 1 copy. Updated by `./deploy.sh <tag>`. User `staging`, password in `k3s/.secrets/staging-password.txt`. |
| Headlamp (cluster GUI) | http://headlamp.localhost:8081 | Log in with a token from `docker exec k3s kubectl -n headlamp create token headlamp-admin`. Full admin rights, so local use only. |
| Kubernetes API | https://127.0.0.1:6443 | For `kubectl`, not a browser. Credentials are in `k3s/kubeconfig/kubeconfig.yaml`. |

The page footer shows which version is running.

## Why these addresses

- **One port, 8081.** All web traffic enters through Traefik, the router built into k3s.
  To use another port, run `K3S_HTTP_PORT=9000 docker compose up -d`.
- **The hostname picks the app.** Traefik sends each request to production, staging or
  Headlamp based on the name in the address (the Ingress rules).
- **`.localhost` needs no setup.** Browsers send any `*.localhost` name to your own PC, so
  you don't need to edit your hosts file or set up DNS. On a real server, swap in real domains.

## More

- [k3s/README.md](k3s/README.md): deploy, promote, rollback and clean-up commands.
- [PLAN.md](PLAN.md): the phased plan (staging, registry, pipeline).
- Without Kubernetes: `cd frontend && docker compose up -d --build` serves the site at http://localhost:8088.
