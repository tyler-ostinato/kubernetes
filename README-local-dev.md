# Local Development Guide

Step-by-step instructions for deploying an app to your local kind cluster using the local Docker registry.

## Prerequisites

Before deploying any app, ensure the cluster and registry are running:

```bash
cd ~/development/kubernetes
just start
```

This starts the kind cluster, the local Docker registry at `localhost:5001`, and the ArgoCD port-forward if installed.

Verify everything is healthy:

```bash
just status
```

---

## Deploying an App

All commands below are run from the **app's own directory** (e.g. `~/development/nordlynx`), not the `kubernetes/` directory.

### Step 1 — Create your `.env` file

Each app that requires secrets has a `.env.example` template:

```bash
cp .env.example .env
```

Open `.env` and fill in the real values. This file is gitignored and never committed.

### Step 2 — Push secrets into the cluster

```bash
just secret
```

This reads your `.env` file and creates (or updates) a Kubernetes Secret in the app's namespace. Re-run this any time you change `.env`.

### Step 3 — Build, push, and deploy

```bash
just deploy
```

This does three things in sequence:
1. Builds the Docker image from the local `Dockerfile`
2. Pushes it to the local registry as `localhost:5001/<app>:dev`
3. Applies all manifests in `k8s/` to the cluster

### Step 4 — Verify the deployment

```bash
kubectl get pods -n <namespace>
kubectl get svc -n <namespace>
```

Pods should reach `Running` within a minute. If a pod is stuck, inspect it:

```bash
kubectl describe pod -n <namespace> <pod-name>
kubectl logs -n <namespace> <pod-name>
```

Or use the app's justfile shortcut:

```bash
just logs
```

### Step 5 — Access the app

Apps are not exposed outside the cluster by default. Use port-forward to reach them locally:

```bash
kubectl port-forward svc/<app-name> -n <namespace> <local-port>:<service-port>
```

Example for an app serving on port 8080:

```bash
kubectl port-forward svc/my-app -n my-app 8080:8080
# Now open http://localhost:8080
```

---

## Iterating

After changing app code or manifests, re-run:

```bash
just deploy
```

After changing secrets in `.env`:

```bash
just secret
kubectl rollout restart deployment/<app-name> -n <namespace>
```

---

## Tearing Down

Remove the app from the cluster without deleting the cluster itself:

```bash
just teardown
```

---

## Cluster Lifecycle

| Command | Effect |
|---|---|
| `just start` | Start cluster + registry; resume if stopped |
| `just stop` | Pause cluster + registry (data preserved) |
| `just status` | Show nodes, pods, registry, ArgoCD state |
| `just reset` | Delete cluster entirely (requires confirmation) |

Run all cluster commands from `~/development/kubernetes`.
