# Adding a New Application — Agent Instructions

This document tells you exactly how to add a new application to this Kubernetes setup. Follow every step in order. Do not deviate from the patterns described here.

The `nordlynx` app at `~/development/nordlynx` is the canonical reference implementation. When in doubt, look at how it is structured.

---

## Conventions

| Convention | Value |
|---|---|
| App directory | `~/development/<app-name>/` |
| Kubernetes namespace | `<app-name>` |
| Local registry image | `localhost:5001/<app-name>:dev` |
| Kubernetes Secret name | `<app-name>-env` |
| ArgoCD manifest | `~/development/kubernetes/apps/<app-name>.yaml` |

Use the app name consistently across all files. For example, for an app called `caddy`: namespace is `caddy`, image is `localhost:5001/caddy:dev`, secret is `caddy-env`.

---

## Step 1 — Read the existing Docker Compose or config

Before creating any files, read the existing app configuration to understand:
- What image it uses
- What ports it exposes
- What environment variables it needs (these become the Secret)
- What Linux capabilities it requires (`NET_ADMIN`, etc.)
- What volumes it mounts
- What sysctls it sets

---

## Step 2 — Create the app directory structure

Create the following layout. Do not put these files inside `~/development/kubernetes/`.

```
~/development/<app-name>/
├── Dockerfile
├── .env.example
├── .gitignore
├── justfile
└── k8s/
    ├── namespace.yaml
    ├── deployment.yaml
    └── service.yaml
```

Create directories with:
```bash
mkdir -p ~/development/<app-name>/k8s
```

---

## Step 3 — Create the Dockerfile

If the app uses an existing public image with no custom build steps, the Dockerfile is a single line:

```dockerfile
FROM <upstream-image>:<tag>
```

If the app requires custom build steps (copying source code, installing dependencies), add them after the `FROM` line as normal.

The Dockerfile exists so the local registry workflow (`docker build → docker push → kubectl apply`) works consistently across all apps.

---

## Step 4 — Create `.env.example` and `.gitignore`

`.env.example` lists every environment variable the app needs, with placeholder values:

```
SOME_API_KEY=your_value_here
SOME_PASSWORD=your_password_here
TZ=America/New_York
```

`.gitignore` must exclude the real `.env`:

```
.env
```

If the app has no secrets or environment variables, skip `.env.example` and omit the `secret` recipe from the justfile (Step 6).

---

## Step 5 — Create Kubernetes manifests

### `k8s/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <app-name>
```

### `k8s/deployment.yaml`

Use this template and fill in the app-specific values:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <app-name>
  namespace: <app-name>
spec:
  replicas: 1
  selector:
    matchLabels:
      app: <app-name>
  template:
    metadata:
      labels:
        app: <app-name>
    spec:
      containers:
        - name: <app-name>
          image: localhost:5001/<app-name>:dev
          imagePullPolicy: Always
          ports:
            - containerPort: <port>
              name: <port-name>
          envFrom:
            - secretRef:
                name: <app-name>-env
```

**Capabilities:** If the app requires Linux capabilities, add a `securityContext` block to the container:

```yaml
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
                - NET_RAW
                # add others as needed
```

**Sysctls:** If the app requires sysctls, add a pod-level `securityContext`. Always comment them out by default with a note — they require additional cluster configuration to enable:

```yaml
    spec:
      # Uncomment to enable unsafe sysctls (requires allowlist in kind-config.yaml)
      # securityContext:
      #   sysctls:
      #     - name: net.ipv4.conf.all.src_valid_mark
      #       value: "1"
```

**No secrets:** If the app has no environment variables, omit the `envFrom` block entirely.

**Static env vars:** For non-secret config values (e.g. log level, mode flags), use `env` directly in the container spec instead of the secret:

```yaml
          env:
            - name: LOG_LEVEL
              value: DEBUG
```

**Volumes:** If the app needs persistent storage, add a `k8s/pvc.yaml` with a static PV backed by a host directory, and mount it. There are two cases:

**Config volume** (`/config`) — backed by the app's local `configs/` directory so settings persist across cluster resets automatically:

```yaml
          volumeMounts:
            - name: config
              mountPath: /config
      volumes:
        - name: config
          persistentVolumeClaim:
            claimName: <app-name>-config
```

`k8s/pvc.yaml`:
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: <app-name>-config
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: ""
  hostPath:
    path: /home/tostinat/development/<app-name>/configs
  claimRef:
    name: <app-name>-config
    namespace: <app-name>
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <app-name>-config
  namespace: <app-name>
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: ""
  volumeName: <app-name>-config
```

Then add the path to `extraMounts` in `~/development/kubernetes/kind-config.yaml` (requires cluster reset if not already present):
```yaml
      - hostPath: /home/tostinat/development/<app-name>/configs
        containerPath: /home/tostinat/development/<app-name>/configs
```

And create the directory on the host before starting the cluster:
```bash
mkdir -p ~/development/<app-name>/configs
```

**Large data volume** (e.g. `/data` on the Seagate) — use the existing seagate mount (already in `kind-config.yaml`), no extra extraMount needed:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: <app-name>-data
spec:
  capacity:
    storage: 2Ti
  accessModes:
    - ReadWriteOnce
  storageClassName: ""
  hostPath:
    path: /mnt/seagate_2tb/media_server/data
  claimRef:
    name: <app-name>-data
    namespace: <app-name>
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: <app-name>-data
  namespace: <app-name>
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Ti
  storageClassName: ""
  volumeName: <app-name>-data
```

### `k8s/service.yaml`

Expose every port the app listens on:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: <app-name>
  namespace: <app-name>
spec:
  selector:
    app: <app-name>
  ports:
    - name: <port-name>
      port: <port>
      targetPort: <port>
```

Add one entry per port. Do not use `NodePort` or `LoadBalancer` — keep services as `ClusterIP`. Access is handled via `kubectl port-forward` during local development.

---

## Step 6 — Create the app justfile

Create `~/development/<app-name>/justfile`. Every app justfile follows this exact structure:

```just
# <app-name> — local dev recipes
# Usage: just <recipe>
# Run from ~/development/<app-name>/

cluster       := env("CLUSTER", "kind")
registry_port := env("REGISTRY_PORT", "5001")
namespace     := "<app-name>"

# Show available recipes
default:
    @just --list

# Build, push to local registry, and apply manifests
deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! docker ps --filter "name=kind-registry" --format "{{{{.Names}}" | grep -q "kind-registry"; then
        echo "✗ Local registry is not running. Run 'just start' from the kubernetes directory." >&2; exit 1
    fi
    echo "=> Building <app-name> image..."
    docker build -t localhost:{{registry_port}}/<app-name>:dev .
    echo "=> Pushing to local registry..."
    docker push localhost:{{registry_port}}/<app-name>:dev
    echo "=> Applying manifests..."
    kubectl apply -f k8s/ --context "kind-{{cluster}}"
    echo "✓ <app-name> deployed."
    echo "  Check status: kubectl get pods -n {{namespace}}"

# Create/update the Secret from .env
secret:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f ".env" ]; then
        echo "✗ .env not found. Copy .env.example and fill in your values." >&2; exit 1
    fi
    kubectl create namespace "{{namespace}}" --context "kind-{{cluster}}" 2>/dev/null || true
    kubectl create secret generic <app-name>-env \
        -n "{{namespace}}" \
        --context "kind-{{cluster}}" \
        --from-env-file=.env \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "✓ <app-name> secret created/updated."

# Stream logs
logs:
    kubectl logs -n "{{namespace}}" --context "kind-{{cluster}}" \
        --all-containers --prefix --follow \
        -l app=<app-name>

# Port-forward to the app's UI or primary port (runs in background).
# Always target the pod directly — svc/ port-forward is less reliable in kind.
forward:
    #!/usr/bin/env bash
    set -euo pipefail
    POD=$(kubectl get pod -n "{{namespace}}" --context "kind-{{cluster}}" \
        -l app=<app-name> -o jsonpath='{.items[0].metadata.name}')
    if [ -z "$POD" ]; then
        echo "✗ No running <app-name> pod found." >&2; exit 1
    fi
    kubectl port-forward -n "{{namespace}}" --context "kind-{{cluster}}" \
        "pod/$POD" <port>:<port> >/tmp/<app-name>-forward.log 2>&1 &
    echo $! > /tmp/<app-name>-forward.pid
    echo "✓ Port-forward running in background (PID $(cat /tmp/<app-name>-forward.pid))"
    echo "  Open:  http://localhost:<port>"
    echo "  Stop:  just forward-stop"
    echo "  Logs:  tail /tmp/<app-name>-forward.log"

# Stop the background port-forward
forward-stop:
    #!/usr/bin/env bash
    if [ ! -f /tmp/<app-name>-forward.pid ]; then
        echo "No port-forward PID file found — nothing to stop." >&2; exit 1
    fi
    kill "$(cat /tmp/<app-name>-forward.pid)" 2>/dev/null \
        && echo "✓ Port-forward stopped." \
        || echo "Process already stopped."
    rm /tmp/<app-name>-forward.pid

# Remove all app resources from the cluster
teardown:
    kubectl delete -f k8s/ --context "kind-{{cluster}}" --ignore-not-found
    echo "✓ <app-name> removed from cluster."
```

Rules:
- Replace every occurrence of `<app-name>` with the real app name
- Replace `<port>` in `open` with the app's primary UI port
- If the app has no secrets, remove the `secret` recipe entirely
- Always use `pod/$POD` in port-forward, not `svc/<app-name>` — service-level port-forward is unreliable in kind
- Do not add app-specific recipes to `~/development/kubernetes/justfile`

### Optional: `restart` recipe

If the app may need a pod restart after manual config edits, add a `restart` recipe:

```just
# Restart the pod
restart:
    kubectl rollout restart deployment/<app-name> \
        -n "{{namespace}}" --context "kind-{{cluster}}"
    kubectl rollout status deployment/<app-name> \
        -n "{{namespace}}" --context "kind-{{cluster}}"
    echo "✓ <app-name> restarted."
```

---

## Step 7 — Create the ArgoCD Application manifest

Create `~/development/kubernetes/apps/<app-name>.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <app-name>
  namespace: argocd
spec:
  project: default
  source:
    # TODO: update repoURL when pushing to Git
    repoURL: https://github.com/YOUR_ORG/<app-name>
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: <app-name>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Leave `repoURL` as a placeholder. The user will update it when they set up the production CI/CD path.

---

## Step 8 — Verify the justfile parses

```bash
cd ~/development/<app-name>
just --list
```

Expected output should show: `default`, `deploy`, `secret` (if applicable), `logs`, `forward`, `teardown`.

---

## What NOT to do

- Do not add app recipes to `~/development/kubernetes/justfile` — that file only manages the cluster itself
- Do not commit `.env` files — they are gitignored by design
- Do not use `imagePullPolicy: Never` — the local registry makes this unnecessary
- Do not use `NodePort` or `LoadBalancer` service types — use `ClusterIP` and `kubectl port-forward` for local access
- Do not create a `secret.yaml` file in `k8s/` — secrets are created imperatively via `just secret` to avoid committing credentials

---

## Checklist

Before finishing, verify:

- [ ] `~/development/<app-name>/Dockerfile` exists
- [ ] `~/development/<app-name>/.env.example` exists (if app has secrets)
- [ ] `~/development/<app-name>/.gitignore` contains `.env`
- [ ] `~/development/<app-name>/k8s/namespace.yaml` exists
- [ ] `~/development/<app-name>/k8s/deployment.yaml` uses image `localhost:5001/<app-name>:dev`
- [ ] `~/development/<app-name>/k8s/service.yaml` exposes correct ports
- [ ] `~/development/<app-name>/justfile` has `deploy`, `logs`, `forward`, `teardown` recipes
- [ ] `~/development/kubernetes/apps/<app-name>.yaml` exists
- [ ] `just --list` runs without errors from the app directory
