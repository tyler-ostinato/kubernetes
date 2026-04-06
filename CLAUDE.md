# Claude Instructions — kubernetes

## Project layout

```
~/development/
├── kubernetes/          ← cluster management (you are here)
│   ├── justfile         ← cluster, registry, ArgoCD, dashboard lifecycle only
│   ├── kind-config.yaml ← cluster creation config (registry mirror + allowed sysctls)
│   ├── apps/            ← ArgoCD Application manifests (one per app)
│   └── manifests/       ← shared cluster-level manifests (e.g. dashboard-admin.yaml)
├── nordlynx/            ← VPN gateway app
├── nellis_auction_monitor/ ← auction scraper app
└── <other-apps>/        ← each app lives in its own directory
```

## Conventions

| Thing | Convention |
|---|---|
| App directory | `~/development/<app-name>/` |
| Kubernetes namespace | `<app-name>` |
| Local registry image | `localhost:5001/<app-name>:dev` |
| Kubernetes Secret name | `<app-name>-env` |
| ArgoCD manifest | `kubernetes/apps/<app-name>.yaml` |
| Cluster name | `kind` |
| Registry name | `kind-registry` |
| Registry port (host) | `5001` |
| Registry port (internal) | `5000` |

## Hard rules

- Never add app-specific recipes to `kubernetes/justfile` — it owns the cluster only
- Never commit `.env` files — secrets go in Kubernetes Secrets via `just secret`
- Never use `imagePullPolicy: Never` — the local registry handles this
- Never use `NodePort` or `LoadBalancer` — use `ClusterIP` + `kubectl port-forward`
- Never create a `secret.yaml` in `k8s/` — secrets are created imperatively

## VPN routing

The `nordlynx` pod runs a `microsocks` sidecar exposing a SOCKS5 proxy at:
`socks5://nordlynx.nordlynx.svc.cluster.local:1080`

Any app that needs VPN routing sets `SOCKS5_PROXY_URL` to this address in its deployment.
See `~/development/nellis_auction_monitor/README-vpn-routing.md` for the full pattern.

## Reference docs

| Task | Read first |
|---|---|
| Adding a new app | `README-new-app.md` — follow every step, use nordlynx as the reference implementation |
| Local dev workflow (deploy, port-forward, iterate) | `README-local-dev.md` |
| Full cluster setup from scratch | `README-local-k8s.md` |
