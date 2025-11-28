#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Deploying Prometheus Monitoring Stack"
echo "=========================================="

# Add Prometheus Community Helm repository
echo "Adding Prometheus Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create namespace if it doesn't exist
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Deploy Prometheus
echo "Deploying Prometheus..."
helm upgrade --install prometheus prometheus-community/prometheus \
    --namespace monitoring \
    --values ../helm/prometheus-values.yaml \
    --wait

echo "✅ Prometheus deployed successfully"

# Deploy PostgreSQL Exporter
echo "Deploying PostgreSQL Exporter..."

# Check if PostgreSQL password secret exists
if kubectl get secret postgresql -n infra &>/dev/null; then
    # Extract PostgreSQL password
    POSTGRES_PASSWORD=$(kubectl get secret postgresql -n infra -o jsonpath='{.data.postgres-password}' | base64 -d)

    # Create PostgreSQL exporter secret
    kubectl create secret generic postgres-exporter-secret \
        --from-literal=DATA_SOURCE_NAME="postgresql://postgres:${POSTGRES_PASSWORD}@postgresql.infra.svc.cluster.local:5432/postgres?sslmode=disable" \
        --namespace monitoring \
        --dry-run=client -o yaml | kubectl apply -f -

    # Deploy PostgreSQL exporter
    helm upgrade --install postgresql-exporter prometheus-community/prometheus-postgres-exporter \
        --namespace monitoring \
        --set serviceMonitor.enabled=true \
        --set serviceMonitor.namespace=monitoring \
        --set config.datasourceSecret.name=postgres-exporter-secret \
        --set config.datasourceSecret.key=DATA_SOURCE_NAME \
        --set resources.limits.cpu=200m \
        --set resources.limits.memory=128Mi \
        --set resources.requests.cpu=100m \
        --set resources.requests.memory=64Mi \
        --wait

    echo "✅ PostgreSQL Exporter deployed"
else
    echo "⚠️  PostgreSQL secret not found. Skipping PostgreSQL Exporter deployment."
    echo "   Deploy PostgreSQL first, then run this script again."
fi

# Deploy Kafka Exporter
echo "Deploying Kafka Exporter..."

if kubectl get statefulset kafka -n infra &>/dev/null; then
    helm upgrade --install kafka-exporter prometheus-community/prometheus-kafka-exporter \
        --namespace monitoring \
        --set kafkaServer={"kafka.infra.svc.cluster.local:9092"} \
        --set serviceMonitor.enabled=true \
        --set serviceMonitor.namespace=monitoring \
        --set resources.limits.cpu=200m \
        --set resources.limits.memory=128Mi \
        --set resources.requests.cpu=100m \
        --set resources.requests.memory=64Mi \
        --wait

    echo "✅ Kafka Exporter deployed"
else
    echo "⚠️  Kafka not found. Skipping Kafka Exporter deployment."
    echo "   Deploy Kafka first, then run this script again."
fi

echo ""
echo "=========================================="
echo "Prometheus Stack Deployment Complete"
echo "=========================================="
echo ""
echo "Access Prometheus:"
echo "  kubectl port-forward -n monitoring svc/prometheus-server 9090:80"
echo "  Then open: http://localhost:9090"
echo ""
echo "Add Prometheus to Grafana:"
echo "  1. Port-forward Grafana: kubectl port-forward -n monitoring svc/loki-grafana 3000:80"
echo "  2. Open Grafana: http://localhost:3000"
echo "  3. Add data source: Configuration → Data Sources → Add Prometheus"
echo "  4. URL: http://prometheus-server.monitoring.svc.cluster.local"
echo ""
echo "Useful queries:"
echo "  - Kafka lag: kafka_consumergroup_lag"
echo "  - PostgreSQL connections: pg_stat_activity_count"
echo "  - Pod CPU usage: container_cpu_usage_seconds_total"
echo "  - Pod memory usage: container_memory_usage_bytes"
echo ""
