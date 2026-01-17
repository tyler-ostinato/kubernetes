# Minikube Cluster with Nginx, Caddy, and ArgoCD

This repository contains the setup for a Minikube cluster running Nginx, Caddy reverse proxy, and ArgoCD.

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/docs/start/) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/) installed
- At least 4GB of free RAM for Minikube

## Quick Start

1. Make the setup script executable:
   ```bash
   chmod +x setup.sh
   ```

2. Run the setup script:
   ```bash
   ./setup.sh
   ```

The script will:
- Start a Minikube cluster
- Install ArgoCD in the `argocd` namespace
- Deploy an Nginx server
- Create ArgoCD Applications for Nginx and Caddy
- Display access credentials

## Accessing Services

### ArgoCD

After running the setup script, ArgoCD will be accessible at:
- **URL**: https://localhost:8080
- **Username**: `admin`
- **Password**: Displayed after setup (from `argocd-initial-admin-secret`)

To get the password manually:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Nginx

Access Nginx using one of these methods:

1. **Via Minikube service** (recommended):
   ```bash
   minikube service nginx-service
   ```

2. **Via NodePort URL**:
   ```bash
   minikube service nginx-service --url
   ```

3. **Port forward**:
   ```bash
   kubectl port-forward svc/nginx-service 8081:80
   ```
   Then access: http://localhost:8081

## Useful Commands

### Check Pod Status
```bash
kubectl get pods -A
```

### Check ArgoCD Status
```bash
kubectl get pods -n argocd
kubectl get svc -n argocd
```

### Check Nginx Status
```bash
kubectl get pods -l app=nginx
kubectl get svc nginx-service
```

### Check Caddy Status
```bash
kubectl get pods -l app=caddy
kubectl get svc caddy-service
```

### Stop Minikube
```bash
minikube stop
```

### Delete Cluster
```bash
minikube delete
```

### Restart Port-Forward for ArgoCD
If the port-forward stops, restart it:
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

## Directory Structure

All manifests are organized into app-specific directories:

```
kubernetes/
├── nginx/
│   └── nginx-deployment.yaml
├── argocd/
│   ├── argocd-namespace.yaml
│   ├── argocd-nginx-application.yaml
│   ├── argocd-nginx-application-template.yaml
│   └── argocd-caddy-application.yaml
├── caddy/
│   ├── Caddyfile
│   ├── caddy-deployment.yaml
│   ├── caddy-service.yaml
│   ├── caddy-configmap.yaml
│   └── caddy-secret.yaml
├── setup.sh
└── README.md
```

## Files

- `setup.sh` - Automated setup script
- `nginx/` - Nginx deployment and service manifests
- `argocd/` - ArgoCD namespace and Application definitions
- `caddy/` - Caddy reverse proxy manifests and configuration

## Troubleshooting

### ArgoCD pods not ready
If ArgoCD pods are not ready after a few minutes:
```bash
kubectl get pods -n argocd
kubectl describe pod <pod-name> -n argocd
```

### Port already in use
If port 8080 is already in use, modify the port-forward command:
```bash
kubectl port-forward -n argocd svc/argocd-server 8082:443
```

### Minikube start issues
If Minikube fails to start, try:
```bash
minikube delete
minikube start --memory=4096 --cpus=2
```

## ArgoCD Applications

ArgoCD Applications have been created that will appear in the ArgoCD UI. Currently, they reference example Git repositories for demonstration purposes.

### Caddy Reverse Proxy

Caddy is configured as a reverse proxy for various self-hosted applications (Portainer, Radarr, Sonarr, Jellyfin, Home Assistant, Grafana). The configuration is copied from `../self_hosted/apps/caddy` but kept separate in this repository.

**Before deploying Caddy**, update the environment variables in `caddy/caddy-secret.yaml`:
- `TLS_EMAIL`: Your email for Let's Encrypt certificates
- `MY_DOMAIN`: Your domain name

**Note**: The Caddyfile references backend services (portainer, radarr, etc.) that may not exist in your minikube cluster. Update the reverse proxy targets in `caddy/caddy-configmap.yaml` or `caddy/Caddyfile` to match your actual service names and ports.

### To Use Your Own Nginx Manifests with ArgoCD:

1. **Create a Git repository** (GitHub, GitLab, Bitbucket, etc.)

2. **Push your nginx manifests** to the repository:
   ```bash
   git init
   git add nginx-deployment.yaml
   git commit -m "Add nginx deployment"
   git remote add origin https://github.com/yourusername/your-repo.git
   git push -u origin main
   ```

3. **Update the ArgoCD Application**:
   - Edit `argocd/argocd-nginx-application.yaml` and update:
     - `repoURL`: Your Git repository URL
     - `targetRevision`: Your branch (e.g., 'main')
     - `path`: Path to your manifests ('.' for root, or 'nginx' for subdirectory)
   - Or use the template: `argocd/argocd-nginx-application-template.yaml`
   
4. **Apply the updated Application**:
   ```bash
   kubectl apply -f argocd/argocd-nginx-application.yaml
   ```

5. **Verify in ArgoCD UI**:
   - Go to https://localhost:8080
   - You should see the nginx application syncing from your Git repository

### Switching from Local to Git

The transition is simple - you only need to update the `source` section in the Application manifest:
- Change `repoURL` to your Git repository URL
- Update `targetRevision` to your branch
- Adjust `path` if needed (e.g., 'nginx' or 'caddy' for app-specific subdirectories)

Your manifest files don't need to change! Just update the Application manifests in the `argocd/` directory.

## Next Steps

After ArgoCD is running, you can:
1. Login to the ArgoCD UI at https://localhost:8080
2. View the Applications dashboard (currently shows example guestbook app)
3. Connect your own Git repositories and create Applications for your nginx deployment
4. Use ArgoCD CLI: `argocd login localhost:8080`

To install ArgoCD CLI:
```bash
# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd
```
