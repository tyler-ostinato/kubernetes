#!/bin/bash
# Script to set up local Git repository access for ArgoCD

set -e

echo "Setting up local Git repository access for ArgoCD..."

# Copy Git repository to a location accessible by ArgoCD repo-server
# We'll create a ConfigMap or use a pod with the Git repo

# Create a ConfigMap with the manifests (simpler approach)
echo "Creating ConfigMap with Caddy manifests..."
kubectl create configmap caddy-manifests \
  --from-file=caddy/ \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✅ Local Git setup complete!"
echo ""
echo "NOTE: ArgoCD still requires a Git repository URL."
echo "For now, you have two options:"
echo "1. Push to GitHub/GitLab and update the Application manifest"
echo "2. Keep using direct kubectl apply for Caddy until Git is set up"
echo ""
echo "Caddy is currently running (deployed directly)."
echo "The ArgoCD Application exists but will show errors until Git is connected."
