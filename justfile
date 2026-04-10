# Local kind cluster manager
# Usage: just <recipe>

cluster            := "kind"
argocd_ns          := "argocd"
argocd_port        := "8080"
argocd_pidfile     := "/tmp/argocd-portforward.pid"
registry_name      := "kind-registry"
registry_port      := "5001"
dashboard_ns       := "kubernetes-dashboard"
dashboard_port     := "8443"
dashboard_pidfile  := "/tmp/dashboard-portforward.pid"

# Show available recipes
default:
    @just --list

# ── Cluster ──────────────────────────────────────────────────────────────────

# Rebuild cluster from scratch and reinstall cluster-level tooling (run after a reset)
provision:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "=> Step 1/3: Starting cluster + registry..."
    just start
    echo ""
    # echo "=> Step 2/3: Installing ArgoCD..."
    # just argocd-install
    # echo ""
    echo "=> Step 3/3: Installing Kubernetes Dashboard..."
    just dashboard-install
    echo ""
    echo "✓ Cluster provisioned. Now redeploy your apps in this order:"
    echo ""
    echo "  cd ~/development/nordlynx               && just secret && just deploy"
    echo "  cd ~/development/caddy                  && just secret && just deploy"
    echo "  cd ~/development/flaresolverr           && just deploy"
    echo "  cd ~/development/prowlarr               && just deploy"
    echo "  cd ~/development/radarr                 && just deploy"
    echo "  cd ~/development/sonarr                 && just deploy"
    echo "  cd ~/development/qbittorrent            && just deploy"
    echo "  cd ~/development/nellis_auction_monitor && just secret && just deploy"

# Start (or resume) the cluster + registry; auto-starts ArgoCD port-forward if installed
start:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! docker info &>/dev/null; then
        echo "✗ Docker is not running. Start Docker first." >&2; exit 1
    fi
    just registry-start
    if docker ps --filter "name={{cluster}}-control-plane" --format "{{{{.Names}}" | grep -q "{{cluster}}-control-plane"; then
        echo "✓ Cluster '{{cluster}}' is already running."
    elif kind get clusters 2>/dev/null | grep -qx "{{cluster}}"; then
        echo "=> Cluster exists but is stopped. Restarting containers..."
        docker start "{{cluster}}-control-plane"
        echo "=> Waiting for API server..."
        for i in $(seq 1 30); do
            kubectl cluster-info --context "kind-{{cluster}}" &>/dev/null && break
            sleep 2
        done
        echo "✓ Cluster '{{cluster}}' is ready."
    else
        echo "=> Creating new kind cluster '{{cluster}}' with registry config..."
        kind create cluster --name "{{cluster}}" --config kind-config.yaml
        just _registry-connect
        just _registry-configmap
        echo "✓ Cluster '{{cluster}}' created."
    fi
    kubectl config use-context "kind-{{cluster}}" &>/dev/null
    echo "✓ kubectl context → kind-{{cluster}}"
    # if kubectl get namespace "{{argocd_ns}}" &>/dev/null; then
    #     just argocd
    # fi

# Stop the cluster + registry (data preserved)
stop:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "{{argocd_pidfile}}" ] && kill -0 "$(cat {{argocd_pidfile}})" 2>/dev/null; then
        kill "$(cat {{argocd_pidfile}})" && rm -f "{{argocd_pidfile}}"
        echo "✓ ArgoCD port-forward stopped."
    fi
    if [ -f "{{dashboard_pidfile}}" ] && kill -0 "$(cat {{dashboard_pidfile}})" 2>/dev/null; then
        kill "$(cat {{dashboard_pidfile}})" && rm -f "{{dashboard_pidfile}}"
        echo "✓ Dashboard port-forward stopped."
    fi
    if docker ps --filter "name={{cluster}}-control-plane" --format "{{{{.Names}}" | grep -q "{{cluster}}-control-plane"; then
        docker stop "{{cluster}}-control-plane"
        echo "✓ Cluster '{{cluster}}' stopped. Data preserved — run 'just start' to resume."
    else
        echo "! Cluster '{{cluster}}' is not running."
    fi
    just registry-stop

# Show cluster, node, pod, registry and ArgoCD status
status:
    #!/usr/bin/env bash
    set -euo pipefail
    echo ""
    echo "Cluster: {{cluster}}"
    echo "──────────────────────────────────────"
    if ! kind get clusters 2>/dev/null | grep -qx "{{cluster}}"; then
        echo "  Cluster:  does not exist"; echo ""; exit 0
    fi
    if docker ps --filter "name={{cluster}}-control-plane" --format "{{{{.Names}}" | grep -q "{{cluster}}-control-plane"; then
        echo "  Cluster:  running"
    else
        echo "  Cluster:  stopped (data preserved)"; echo ""; exit 0
    fi
    if docker ps --filter "name={{registry_name}}" --format "{{{{.Names}}" | grep -q "{{registry_name}}"; then
        echo "  Registry: running at localhost:{{registry_port}}"
    else
        echo "  Registry: stopped"
    fi
    echo ""
    echo "Nodes:"
    kubectl get nodes --context "kind-{{cluster}}" 2>/dev/null || echo "  (unreachable)"
    echo ""
    echo "Pods (all namespaces):"
    kubectl get pods -A --context "kind-{{cluster}}" 2>/dev/null || echo "  (unreachable)"
    echo ""
    if kubectl get namespace "{{argocd_ns}}" --context "kind-{{cluster}}" &>/dev/null; then
        if [ -f "{{argocd_pidfile}}" ] && kill -0 "$(cat {{argocd_pidfile}})" 2>/dev/null; then
            echo "  ArgoCD UI: https://localhost:{{argocd_port}} (port-forward active, PID $(cat {{argocd_pidfile}}))"
        else
            echo "  ArgoCD UI: installed but port-forward not running — run 'just argocd'"
        fi
    else
        echo "  ArgoCD: not installed"
    fi
    echo ""

# Delete the cluster and all its data (requires confirmation)
reset:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "WARNING: This will permanently delete cluster '{{cluster}}' and all its data."
    read -r -p "Type the cluster name to confirm: " confirm
    if [ "$confirm" != "{{cluster}}" ]; then echo "Aborted."; exit 0; fi
    if [ -f "{{argocd_pidfile}}" ] && kill -0 "$(cat {{argocd_pidfile}})" 2>/dev/null; then
        kill "$(cat {{argocd_pidfile}})" && rm -f "{{argocd_pidfile}}"
    fi
    kind delete cluster --name "{{cluster}}"
    echo "✓ Cluster '{{cluster}}' deleted."
    echo "  Registry is still running. Use 'just registry-stop' to stop it or 'just start' to recreate the cluster."

# ── Registry ─────────────────────────────────────────────────────────────────

# Start the local Docker registry (idempotent)
registry-start:
    #!/usr/bin/env bash
    set -euo pipefail
    if docker ps --filter "name={{registry_name}}" --format "{{{{.Names}}" | grep -q "{{registry_name}}"; then
        echo "✓ Registry already running at localhost:{{registry_port}}"
        exit 0
    fi
    if docker ps -a --filter "name={{registry_name}}" --format "{{{{.Names}}" | grep -q "{{registry_name}}"; then
        echo "=> Restarting existing registry container..."
        docker start "{{registry_name}}"
    else
        echo "=> Starting local registry at localhost:{{registry_port}}..."
        docker run -d \
            --name "{{registry_name}}" \
            --restart=always \
            -p "127.0.0.1:{{registry_port}}:5000" \
            registry:2
    fi
    echo "✓ Registry running at localhost:{{registry_port}}"

# Stop the local Docker registry
registry-stop:
    #!/usr/bin/env bash
    set -euo pipefail
    if docker ps --filter "name={{registry_name}}" --format "{{{{.Names}}" | grep -q "{{registry_name}}"; then
        docker stop "{{registry_name}}"
        echo "✓ Registry stopped."
    else
        echo "! Registry is not running."
    fi

# List all images in the local registry
registry-list:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Images in local registry (localhost:{{registry_port}}):"
    curl -s http://localhost:{{registry_port}}/v2/_catalog 2>/dev/null \
        | python3 -c "import sys,json; repos=json.load(sys.stdin).get('repositories',[]); [print('  ' + r) for r in repos] if repos else print('  (empty)')"

# Connect registry to the kind network (run automatically on cluster create)
_registry-connect:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! docker network inspect kind &>/dev/null; then
        echo "! kind network not found — cluster may not be running." >&2; exit 1
    fi
    if docker network inspect kind --format '{{{{range .Containers}}{{{{.Name}} {{{{end}}}}' | grep -q "{{registry_name}}"; then
        echo "✓ Registry already connected to kind network."
    else
        docker network connect kind "{{registry_name}}"
        echo "✓ Registry connected to kind network."
    fi

# Apply the registry ConfigMap (advertises the registry to tooling)
_registry-configmap:
    #!/usr/bin/env bash
    set -euo pipefail
    kubectl apply -f - --context "kind-{{cluster}}" <<EOF
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: local-registry-hosting
      namespace: kube-public
    data:
      localRegistryHosting.v1: |
        host: "localhost:{{registry_port}}"
        help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
    EOF
    echo "✓ Registry ConfigMap applied."

# ── ArgoCD ───────────────────────────────────────────────────────────────────

# Install ArgoCD into the cluster
argocd-install:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! kubectl cluster-info --context "kind-{{cluster}}" &>/dev/null; then
        echo "✗ Cluster is not running." >&2; exit 1
    fi
    echo "=> Creating argocd namespace..."
    kubectl create namespace "{{argocd_ns}}" --context "kind-{{cluster}}" 2>/dev/null || echo "  (namespace already exists)"
    echo "=> Installing ArgoCD..."
    kubectl apply -n "{{argocd_ns}}" --context "kind-{{cluster}}" \
        --server-side --force-conflicts \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    echo "=> Waiting for argocd-server rollout (this takes a minute)..."
    kubectl rollout status deployment/argocd-server \
        -n "{{argocd_ns}}" --context "kind-{{cluster}}" --timeout=300s
    echo "✓ ArgoCD installed."
    just argocd
    just password

# Start ArgoCD port-forward in the background
argocd:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "{{argocd_pidfile}}" ] && kill -0 "$(cat {{argocd_pidfile}})" 2>/dev/null; then
        echo "✓ ArgoCD port-forward already active on https://localhost:{{argocd_port}} (PID $(cat {{argocd_pidfile}}))"
        exit 0
    fi
    stale_pid=$(ss -tlnp "sport = :{{argocd_port}}" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1 || true)
    if [ -n "$stale_pid" ]; then
        echo "=> Port {{argocd_port}} held by PID $stale_pid — killing stale process..."
        kill "$stale_pid" 2>/dev/null || true
        sleep 1
    fi
    echo "=> Waiting for argocd-server to be available..."
    kubectl wait --for=condition=available deployment/argocd-server \
        -n "{{argocd_ns}}" --timeout=120s --context "kind-{{cluster}}" &>/dev/null \
        || echo "! argocd-server may not be fully ready — starting port-forward anyway."
    kubectl port-forward svc/argocd-server \
        -n "{{argocd_ns}}" --context "kind-{{cluster}}" \
        "{{argocd_port}}:443" &>/dev/null &
    echo $! > "{{argocd_pidfile}}"
    sleep 1
    if kill -0 "$(cat {{argocd_pidfile}})" 2>/dev/null; then
        echo "✓ ArgoCD UI available at https://localhost:{{argocd_port}}"
        echo "  Run 'just password' to get the admin password."
    else
        echo "✗ Port-forward failed. Is ArgoCD installed?" >&2
        rm -f "{{argocd_pidfile}}"; exit 1
    fi

# Print the ArgoCD admin password
password:
    #!/usr/bin/env bash
    set -euo pipefail
    pass=$(kubectl -n "{{argocd_ns}}" get secret argocd-initial-admin-secret \
        --context "kind-{{cluster}}" \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d) || {
        echo "✗ Could not retrieve password. ArgoCD may not be installed or the secret was deleted." >&2; exit 1
    }
    echo ""
    echo "ArgoCD credentials:"
    echo "  URL:      https://localhost:{{argocd_port}}"
    echo "  Username: admin"
    echo "  Password: $pass"
    echo ""
    echo "! Change this password after your first login."

# ── Dashboard ────────────────────────────────────────────────────────────────

# Install Kubernetes Dashboard and create an admin service account
dashboard-install:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! kubectl cluster-info --context "kind-{{cluster}}" &>/dev/null; then
        echo "✗ Cluster is not running." >&2; exit 1
    fi
    echo "=> Installing Kubernetes Dashboard..."
    kubectl apply --context "kind-{{cluster}}" \
        -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
    echo "=> Creating admin service account..."
    kubectl apply --context "kind-{{cluster}}" -f manifests/dashboard-admin.yaml
    echo "=> Waiting for dashboard rollout..."
    kubectl rollout status deployment/kubernetes-dashboard \
        -n "{{dashboard_ns}}" --context "kind-{{cluster}}" --timeout=120s
    echo "✓ Dashboard installed."
    just dashboard

# Open the Kubernetes Dashboard (port-forward + print token)
dashboard:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f "{{dashboard_pidfile}}" ] && kill -0 "$(cat {{dashboard_pidfile}})" 2>/dev/null; then
        echo "✓ Dashboard already running at https://localhost:{{dashboard_port}}"
    else
        stale_pid=$(ss -tlnp "sport = :{{dashboard_port}}" 2>/dev/null | grep -oP 'pid=\K[0-9]+' | head -1 || true)
        if [ -n "$stale_pid" ]; then
            kill "$stale_pid" 2>/dev/null || true
            sleep 1
        fi
        kubectl port-forward svc/kubernetes-dashboard \
            -n "{{dashboard_ns}}" --context "kind-{{cluster}}" \
            "{{dashboard_port}}:443" &>/dev/null &
        echo $! > "{{dashboard_pidfile}}"
        sleep 1
        if ! kill -0 "$(cat {{dashboard_pidfile}})" 2>/dev/null; then
            echo "✗ Port-forward failed. Run 'just dashboard-install' first." >&2
            rm -f "{{dashboard_pidfile}}"; exit 1
        fi
        echo "✓ Dashboard available at https://localhost:{{dashboard_port}}"
    fi
    echo ""
    echo "Token (paste into the browser login screen):"
    kubectl get secret admin-user-token \
        -n "{{dashboard_ns}}" --context "kind-{{cluster}}" \
        -o jsonpath="{.data.token}" | base64 -d
    echo ""

# ── Logs ─────────────────────────────────────────────────────────────────────

# Stream logs from a namespace (default: argocd)
logs ns=argocd_ns:
    kubectl logs -n "{{ns}}" --context "kind-{{cluster}}" \
        --all-containers --prefix --follow \
        -l "app.kubernetes.io/part-of=argocd" 2>/dev/null \
    || kubectl logs -n "{{ns}}" --context "kind-{{cluster}}" \
        --all-containers --prefix --follow 2>/dev/null \
    || echo "No pods found in namespace '{{ns}}'"
