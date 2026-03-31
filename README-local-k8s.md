# Local Kubernetes Cluster Setup with kind + ArgoCD

This guide sets up a local Kubernetes cluster for development and testing, with ArgoCD for GitOps-based application management.

## Prerequisites

- **OS**: Linux
- **Container Runtime**: Docker (installed and running)
- **Resources**: 4-8 CPU cores, 8-16GB RAM available
- **Tools**: Docker must be verified working (`docker ps`)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Local Machine                         │
│                                                          │
│   ┌─────────────────────┐    ┌─────────────────────┐   │
│   │    kind Cluster     │    │    ArgoCD           │   │
│   │                     │    │                     │   │
│   │  ┌───────────────┐  │    │  ┌───────────────┐  │   │
│   │  │ Control Plane │  │    │  │ API Server    │  │   │
│   │  │    (node)     │  │    │  │   :8080       │  │   │
│   │  └───────────────┘  │    │  └───────────────┘  │   │
│   │                     │    │                     │   │
│   │  ┌───────────────┐  │    │  ┌───────────────┐  │   │
│   │  │   Worker     │  │    │  │  UI Dashboard │  │   │
│   │  │   (node)     │  │    │  │   (Browser)   │  │   │
│   │  └───────────────┘  │    │  └───────────────┘  │   │
│   └─────────────────────┘    └─────────────────────┘   │
│                                                          │
│   Access: kubectl / Browser                              │
└─────────────────────────────────────────────────────────┘
```

## Phases

### Phase 1: Install CLI Tools

```bash
# Install kind (Kubernetes in Docker)
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x kind
sudo mv kind /usr/local/bin/

# Install kubectl
curl -Lo kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Verify installations
kind version
kubectl version --client
```

### Phase 2: Verify Docker and Resources

```bash
# Verify Docker is running
docker info

# Check available resources
free -h
nproc
```

### Phase 3: Create kind Cluster

```bash
# Create a single-node cluster (default)
kind create cluster

# Or create with custom config (example: multi-node)
# kind create cluster --name my-cluster --config kind-config.yaml

# Verify cluster is running
kubectl get nodes
kubectl cluster-info
```

### Phase 4: Install ArgoCD

```bash
# Create argocd namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all pods to be ready
kubectl get pods -n argocd -w
```

### Phase 5: Access ArgoCD UI

```bash
# Port-forward ArgoCD server to localhost:8080
kubectl port-forward svc/argocd-server -n argocd 8080:443

# In another terminal, get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

**Access**: Open browser to `https://localhost:8080`

**Login**:
- Username: `admin`
- Password: (from command above)

**Change password** after first login.

### Phase 6: Test with Guestbook App

1. In ArgoCD UI, click **+ New App**
2. Configure:
   - **Application Name**: `guestbook`
   - **Project**: `default`
   - **Sync Policy**: `Automatic`
   - **Repository URL**: `https://github.com/argoproj/argocd-example-apps`
   - **Revision**: `HEAD`
   - **Path**: `guestbook`
   - **Cluster URL**: `https://kubernetes.default.svc`
   - **Namespace**: `default`
3. Click **Create**
4. Click **Sync** to deploy
5. Verify pods: `kubectl get pods`

### Phase 7: Your Development Workflow

#### Option A: Local Development (kubectl)

```bash
# Apply manifests directly during development
kubectl apply -f ./your-app/

# Test changes immediately
kubectl get pods -n your-namespace
kubectl describe deployment -n your-namespace
```

#### Option B: GitOps Workflow (ArgoCD)

1. **Develop locally** with `kubectl apply`
2. **Push manifests** to Git repository:
   ```bash
   git add .
   git commit -m "Your changes"
   git push origin main
   ```
3. **Create ArgoCD Application** pointing to your repo:
   ```bash
   # Example Application manifest
   cat <<EOF | kubectl apply -f -
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: your-app
     namespace: argocd
   spec:
     project: default
     source:
       repoURL: https://github.com/your-org/your-repo
       targetRevision: HEAD
       path: ./manifests
     destination:
       server: https://kubernetes.default.svc
       namespace: default
     syncPolicy:
       automated:
         prune: true
         selfHeal: true
   EOF
   ```
4. ArgoCD syncs automatically on `git push`
5. View sync status in ArgoCD UI

## Optional Tools

### Install Helm

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### Install k9s (Terminal UI)

```bash
# Download k9s
curl -Lo k9s.tar.gz https://github.com/derailed/k9s/releases/download/v0.32.4/k9s_Linux_amd64.tar.gz
tar -xzf k9s.tar.gz
sudo mv k9s /usr/local/bin/
k9s version
```

### Install stern (Log Tailing)

```bash
# Download stern
curl -Lo stern https://github.com/stern/stern/releases/download/v1.28.0/stern_1.28.0_linux_amd64.tar.gz
tar -xzf stern -C /usr/local/bin/
stern --version

# Usage: tail logs from multiple pods
stern your-app -n your-namespace
```

## Useful Commands

```bash
# Cluster management
kind get clusters
kind delete cluster
kind delete cluster --name my-cluster

# kubectl shortcuts
kubectl get all -A
kubectl get pods -n argocd
kubectl describe pod -n argocd
kubectl logs -n argocd deployment/argocd-server

# ArgoCD CLI (optional)
brew install argocd  # macOS
# or
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd

# ArgoCD CLI login
argocd login localhost:8080 --username admin --password YOUR_PASSWORD --insecure

# Sync app via CLI
argocd app sync guestbook
```

## Troubleshooting

### Pods not starting

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### ArgoCD login issues

#### Get the initial admin password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

#### Change the admin password

Use `read -s` to avoid the password appearing in shell history. Paste this entire block at once — it will prompt you to type the password:

```bash
read -s -p "Enter new password: " PASS && echo

HASH=$(python3 -c "import bcrypt, sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt(rounds=10)).decode())" "$PASS")

kubectl -n argocd patch secret argocd-secret \
  -p "{\"stringData\": {\"admin.password\": \"$HASH\", \"admin.passwordMtime\": \"$(date +%FT%T%Z)\"}}"

kubectl rollout restart deployment argocd-server -n argocd
```

Wait ~30 seconds for the pod to restart, then log in with username `admin` and your new password.

> **Note**: The username is always `admin` — ArgoCD does not support renaming the built-in account. For named users, configure SSO (GitHub, Google, Okta, etc.).

### Cluster connectivity issues

```bash
# Verify kind cluster
kind get clusters
docker ps  # should show kind-* containers

# Recreate cluster if needed
kind delete cluster
kind create cluster
```

## Cleanup

```bash
# Delete ArgoCD
kubectl delete -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Delete cluster
kind delete cluster
```

## References

- [kind Documentation](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Example Apps](https://github.com/argoproj/argocd-example-apps)
