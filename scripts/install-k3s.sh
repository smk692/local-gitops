#!/bin/bash

set -e

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "================================================"
echo "Mac Mini k3s Installation Script"
echo "================================================"

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Error: This script is designed for macOS (Darwin)"
    exit 1
fi

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install required tools
echo "Installing required tools..."
brew install kubectl helm k3d

# Check if k3d cluster already exists
if k3d cluster list | grep -q "macmini-cluster"; then
    echo "k3d cluster 'macmini-cluster' already exists"
    read -p "Do you want to delete and recreate it? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing cluster..."
        k3d cluster delete macmini-cluster
    else
        echo "Using existing cluster"
        kubectl config use-context k3d-macmini-cluster
        exit 0
    fi
fi

# Create persistent storage directory
STORAGE_DIR="$HOME/.k3d/storage"
mkdir -p "$STORAGE_DIR"
echo "Using storage directory: $STORAGE_DIR"

# Create k3d cluster using declarative config file
K3D_CONFIG="$PROJECT_ROOT/k3d/k3d-config.yaml"
echo "Creating k3d cluster using config: $K3D_CONFIG"

if [[ -f "$K3D_CONFIG" ]]; then
    k3d cluster create --config "$K3D_CONFIG"
else
    echo "Warning: k3d config file not found, falling back to inline configuration..."
    k3d cluster create macmini-cluster \
        --api-port 6550 \
        --servers 1 \
        --agents 0 \
        --port "8080:80@loadbalancer" \
        --port "8443:443@loadbalancer" \
        --volume "$STORAGE_DIR":/var/lib/rancher/k3s/storage@all \
        --k3s-arg "--disable=traefik@server:0"
fi

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
sleep 10
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Set context
kubectl config use-context k3d-macmini-cluster

# Add Helm repositories
echo "Adding Helm repositories..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Create namespaces
echo "Creating namespaces..."
kubectl apply -f ../k8s/namespaces/namespaces.yaml

# Install NGINX Ingress Controller using values file
INGRESS_VALUES="$PROJECT_ROOT/helm/ingress-nginx-values.yaml"
echo "Installing NGINX Ingress Controller..."

if [[ -f "$INGRESS_VALUES" ]]; then
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace kube-system \
        --values "$INGRESS_VALUES"
else
    echo "Warning: Ingress values file not found, using default settings..."
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace kube-system \
        --set controller.service.type=LoadBalancer \
        --set controller.service.ports.http=80 \
        --set controller.service.ports.https=443
fi

# Wait for ingress controller to be ready
echo "Waiting for ingress controller..."
kubectl wait --namespace kube-system \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=300s

echo "================================================"
echo "k3s Installation Complete!"
echo "================================================"
echo ""
echo "Cluster Information:"
kubectl cluster-info
echo ""
echo "Nodes:"
kubectl get nodes
echo ""
echo "Namespaces:"
kubectl get namespaces
echo ""
echo "Next steps:"
echo "1. Deploy Kafka: ./deploy-kafka.sh"
echo "2. Deploy PostgreSQL: ./deploy-postgres.sh"
echo "3. Deploy monitoring stack: ./deploy-monitoring.sh"
