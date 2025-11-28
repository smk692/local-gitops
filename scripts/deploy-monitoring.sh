#!/bin/bash

set -e

echo "================================================"
echo "Deploying Loki Monitoring Stack to k3d cluster"
echo "================================================"

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: kubectl is not configured. Run install-k3s.sh first."
    exit 1
fi

# Check if monitoring namespace exists
if ! kubectl get namespace monitoring &> /dev/null; then
    echo "Error: 'monitoring' namespace does not exist. Run install-k3s.sh first."
    exit 1
fi

# Add Grafana Helm repo
echo "Adding/updating Grafana Helm repository..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Loki Stack using Helm
echo "Installing Loki Stack (Loki + Promtail + Grafana)..."
helm upgrade --install loki grafana/loki-stack \
    --namespace monitoring \
    --values ../helm/loki-values.yaml \
    --wait \
    --timeout 10m

# Wait for Loki to be ready
echo "Waiting for Loki pods to be ready..."
kubectl wait --namespace monitoring \
    --for=condition=ready pod \
    --selector=app=loki \
    --timeout=600s

# Wait for Grafana to be ready
echo "Waiting for Grafana to be ready..."
kubectl wait --namespace monitoring \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=grafana \
    --timeout=600s

# Deploy Grafana Ingress
echo "Deploying Grafana Ingress..."
kubectl apply -f ../k8s/monitoring/grafana-ingress.yaml

# Get Grafana admin password
GRAFANA_PASSWORD=$(kubectl get secret --namespace monitoring loki-grafana -o jsonpath="{.data.admin-password}" | base64 -d)

echo "================================================"
echo "Loki Monitoring Stack Deployment Complete!"
echo "================================================"
echo ""
echo "Monitoring Services:"
kubectl get svc -n monitoring
echo ""
echo "Monitoring Pods:"
kubectl get pods -n monitoring
echo ""
echo "Access Grafana:"
echo "  Local: kubectl port-forward -n monitoring svc/loki-grafana 3001:80"
echo "  Then visit: http://localhost:3001"
echo "  Username: admin"
echo "  Password: $GRAFANA_PASSWORD"
echo ""
echo "Loki endpoint (internal):"
echo "  http://loki.monitoring.svc.cluster.local:3100"
echo ""
echo "View logs with LogCLI:"
echo "  kubectl port-forward -n monitoring svc/loki 3100:3100"
echo "  logcli query '{namespace=\"backend\"}'"
echo ""
echo "Promtail is collecting logs from all namespaces automatically"
