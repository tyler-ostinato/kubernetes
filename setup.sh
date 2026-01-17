#!/bin/bash

set -e

# Add ~/.local/bin to PATH if it exists and isn't already there
export PATH="$HOME/.local/bin:$PATH"

echo "🚀 Setting up Minikube cluster with Nginx and ArgoCD..."

# Check if minikube is installed
if ! command -v minikube &> /dev/null; then
    echo "❌ Minikube is not installed. Please install it first:"
    echo "   Visit: https://minikube.sigs.k8s.io/docs/start/"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install it first."
    exit 1
fi

# Start minikube cluster
echo "📦 Starting Minikube cluster..."
minikube start --memory=4096 --cpus=2

# Wait for minikube to be ready
echo "⏳ Waiting for Minikube to be ready..."
minikube status

# Enable ingress addon (useful for ArgoCD)
echo "🔧 Enabling ingress addon..."
minikube addons enable ingress

# Create argocd namespace
echo "📁 Creating ArgoCD namespace..."
kubectl apply -f argocd/argocd-namespace.yaml

# Install ArgoCD
echo "⚙️  Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "⏳ Waiting for ArgoCD pods to be ready (this may take a few minutes)..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || true
kubectl wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/name=argocd-server -n argocd || true
# Wait for repo-server which fetches Git repositories
echo "⏳ Waiting for ArgoCD repo-server to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd || true
kubectl wait --for=condition=ready --timeout=300s pod -l app.kubernetes.io/name=argocd-repo-server -n argocd || true
# Give repo-server additional time to fully initialize
sleep 10

# Deploy Caddy reverse proxy
echo "🌐 Deploying Caddy..."
kubectl apply -f caddy/caddy-secret.yaml
kubectl apply -f caddy/caddy-configmap.yaml
kubectl apply -f caddy/caddy-deployment.yaml
kubectl apply -f caddy/caddy-service.yaml

# Wait for Caddy to be ready
echo "⏳ Waiting for Caddy to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/caddy -n default || true

# Get ArgoCD admin password
echo ""
echo "🔑 Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Get minikube IP
MINIKUBE_IP=$(minikube ip)

# Port-forward ArgoCD server in background
echo ""
echo "🔌 Setting up port-forward for ArgoCD (this will run in background)..."
kubectl port-forward -n argocd svc/argocd-server 8080:443 > /dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Wait a moment for port-forward to establish
sleep 2

echo ""
echo "✅ Setup complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Access Information:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🌐 ArgoCD:"
echo "   URL: https://localhost:8080"
echo "   Username: admin"
echo "   Password: $ARGOCD_PASSWORD"
echo "   Get password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d"
echo ""
echo "🌐 Caddy:"
echo "   URL: http://$MINIKUBE_IP"
echo "   Or run: minikube service caddy-service"
echo "   HTTP: minikube service caddy-service --http"
echo "   HTTPS: minikube service caddy-service"
echo ""
echo "📝 To view ArgoCD UI, open: https://localhost:8080"
echo "   (Ignore the SSL warning and proceed)"
echo ""
echo "🛑 To stop the port-forward, run: kill $PORT_FORWARD_PID"
echo "🛑 To stop Minikube, run: minikube stop"
echo ""
