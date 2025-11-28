#!/bin/bash

set -e

echo "================================================"
echo "Setting up Networking and Ingress"
echo "================================================"

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: kubectl is not configured. Run install-k3s.sh first."
    exit 1
fi

# Apply network policies
echo "Applying network policies..."
kubectl apply -f ../k8s/ingress/network-policy.yaml

echo ""
echo "================================================"
echo "Networking Setup Complete!"
echo "================================================"
echo ""
echo "Network Policies:"
kubectl get networkpolicies --all-namespaces
echo ""
echo "Ingress Resources:"
kubectl get ingress --all-namespaces
echo ""
echo "================================================"
echo "Local DNS Setup Required"
echo "================================================"
echo ""
echo "Add these entries to your /etc/hosts file:"
echo ""
cat ../k8s/ingress/hosts-config.yaml | grep "127.0.0.1"
echo ""
echo "To edit /etc/hosts:"
echo "  sudo nano /etc/hosts"
echo ""
echo "After updating /etc/hosts, you can access:"
echo "  - Frontend:    http://app.local:8080"
echo "  - Backend API: http://api.local:8080/api"
echo "  - Kafka UI:    http://kafka-ui.local:8080"
echo "  - pgAdmin:     http://pgadmin.local:8080"
echo "  - Grafana:     http://grafana.local:8080"
echo ""
echo "Note: Port 8080 is mapped to the ingress controller"
