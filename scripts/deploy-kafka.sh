#!/bin/bash

set -e

echo "================================================"
echo "Deploying Kafka to k3d cluster"
echo "================================================"

# Check if kubectl is configured
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: kubectl is not configured. Run install-k3s.sh first."
    exit 1
fi

# Check if infra namespace exists
if ! kubectl get namespace infra &> /dev/null; then
    echo "Error: 'infra' namespace does not exist. Run install-k3s.sh first."
    exit 1
fi

# Add Bitnami Helm repo if not already added
echo "Adding/updating Bitnami Helm repository..."
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Clean up any previous failed deployments
echo "Checking for previous failed deployments..."
if helm list -n infra | grep -q "kafka"; then
    echo "Found existing Kafka release, uninstalling..."
    helm uninstall kafka -n infra --wait || true
    sleep 5
fi

# Clean up any orphaned resources
echo "Cleaning up any orphaned resources..."
kubectl delete statefulset -n infra -l app.kubernetes.io/name=kafka --force --grace-period=0 2>/dev/null || true
kubectl delete pod -n infra -l app.kubernetes.io/name=kafka --force --grace-period=0 2>/dev/null || true
sleep 5

# Install Kafka using Helm chart 31.5.0 (Kafka 3.9.0)
echo "Installing Kafka with Bitnami chart 31.5.0 (Kafka 3.9.0)..."
helm upgrade --install kafka bitnami/kafka \
    --version 31.5.0 \
    --namespace infra \
    --values ../helm/kafka-values.yaml \
    --wait \
    --timeout 15m

# Verify Kafka deployment
echo "Verifying Kafka deployment..."
kubectl get pods -n infra -l app.kubernetes.io/name=kafka

# Deploy Kafka UI
echo "Deploying Kafka UI..."
kubectl apply -f ../k8s/kafka/kafka-ui.yaml

# Wait for Kafka UI to be ready
echo "Waiting for Kafka UI to be ready..."
kubectl wait --namespace infra \
    --for=condition=ready pod \
    --selector=app=kafka-ui \
    --timeout=300s

echo "================================================"
echo "Kafka Deployment Complete!"
echo "================================================"
echo ""
echo "Kafka Service Information:"
kubectl get svc -n infra | grep kafka
echo ""
echo "Kafka Pods:"
kubectl get pods -n infra | grep kafka
echo ""
echo "Access Kafka UI:"
echo "  Local: kubectl port-forward -n infra svc/kafka-ui 8080:8080"
echo "  Then visit: http://localhost:8080"
echo ""
echo "Kafka Bootstrap Server (internal):"
echo "  kafka.infra.svc.cluster.local:9092"
echo ""
echo "Test Kafka connection:"
echo "  kubectl run kafka-test-client --restart='Never' --image docker.io/bitnami/kafka:latest --namespace infra --command -- sleep infinity"
echo "  kubectl exec --tty -i kafka-test-client --namespace infra -- bash"
echo "  Then run: kafka-topics.sh --list --bootstrap-server kafka:9092"
