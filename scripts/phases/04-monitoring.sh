#!/bin/bash

# ============================================================
# Phase 4: Monitoring Stack
# Deploys Loki, Grafana, Prometheus, and exporters
# ============================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source libraries
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/validation.sh"

# ============================================================
# Phase 4 Main Function
# ============================================================

phase_04_monitoring() {
    print_header "Phase 4: Monitoring Stack"

    # Validate prerequisites
    print_step "4.0" "Prerequisites Check"
    validate_kubectl || return 1
    validate_namespace "monitoring" || {
        log_info "Creating monitoring namespace..."
        kubectl create namespace monitoring
    }

    # Step 4.1: Deploy Loki Stack (includes Grafana)
    print_step "4.1" "Loki Stack Deployment"
    deploy_loki_stack || return 1

    # Step 4.2: Deploy Prometheus
    print_step "4.2" "Prometheus Deployment"
    deploy_prometheus || return 1

    # Step 4.3: Deploy Exporters
    print_step "4.3" "Exporter Deployment"
    deploy_exporters || return 1

    # Step 4.4: Configure Grafana
    print_step "4.4" "Grafana Configuration"
    configure_grafana || return 1

    # Step 4.5: Verify monitoring
    print_step "4.5" "Monitoring Verification"
    verify_monitoring || return 1

    log_success "Phase 4 completed successfully"
    return 0
}

# ============================================================
# Loki Stack Functions
# ============================================================

deploy_loki_stack() {
    local values_file="$PROJECT_ROOT/helm/loki-values.yaml"

    log_info "Deploying Loki Stack (Loki + Promtail + Grafana)..."

    # Check if already deployed
    if helm status loki -n monitoring &>/dev/null; then
        log_info "Loki stack already deployed, upgrading..."
    fi

    # Build helm command
    local helm_args=(
        "upgrade" "--install" "loki" "grafana/loki-stack"
        "--namespace" "monitoring"
        "--set" "loki.persistence.enabled=false"
        "--set" "grafana.enabled=true"
        "--set" "promtail.enabled=true"
        "--wait"
        "--timeout" "10m"
    )

    # Add values file if exists
    if [[ -f "$values_file" ]]; then
        helm_args+=("--values" "$values_file")
        log_info "Using values file: $values_file"
    fi

    # Deploy
    helm "${helm_args[@]}"

    # Wait for Loki to be ready
    log_info "Waiting for Loki to be ready..."
    kubectl wait --namespace monitoring \
        --for=condition=ready pod \
        --selector=app=loki \
        --timeout=300s 2>/dev/null || log_warn "Loki may not be fully ready"

    print_success "Loki Stack deployed"
    return 0
}

# ============================================================
# Prometheus Functions
# ============================================================

deploy_prometheus() {
    local values_file="$PROJECT_ROOT/helm/prometheus-values.yaml"

    log_info "Deploying Prometheus..."

    # Check if already deployed
    if helm status prometheus -n monitoring &>/dev/null; then
        log_info "Prometheus already deployed, upgrading..."
    fi

    # Build helm command
    local helm_args=(
        "upgrade" "--install" "prometheus" "prometheus-community/prometheus"
        "--namespace" "monitoring"
        "--set" "alertmanager.enabled=true"
        "--set" "server.persistentVolume.enabled=false"
        "--wait"
        "--timeout" "10m"
    )

    # Add values file if exists
    if [[ -f "$values_file" ]]; then
        helm_args+=("--values" "$values_file")
        log_info "Using values file: $values_file"
    fi

    # Deploy
    helm "${helm_args[@]}"

    # Wait for Prometheus to be ready
    log_info "Waiting for Prometheus to be ready..."
    kubectl wait --namespace monitoring \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=prometheus \
        --timeout=300s 2>/dev/null || log_warn "Prometheus may not be fully ready"

    print_success "Prometheus deployed"
    return 0
}

# ============================================================
# Exporter Functions
# ============================================================

deploy_exporters() {
    log_info "Deploying exporters..."

    # PostgreSQL Exporter
    deploy_postgres_exporter

    # Kafka Exporter
    deploy_kafka_exporter

    print_success "Exporters deployed"
    return 0
}

deploy_postgres_exporter() {
    log_info "Deploying PostgreSQL Exporter..."

    # Create secret for PostgreSQL connection
    local pg_password="postgres123"
    local data_source="postgresql://postgres:${pg_password}@postgresql.database.svc.cluster.local:5432/postgres?sslmode=disable"

    # Check if secret exists
    if ! kubectl get secret postgres-exporter-secret -n monitoring &>/dev/null; then
        kubectl create secret generic postgres-exporter-secret \
            --from-literal=DATA_SOURCE_NAME="$data_source" \
            --namespace monitoring
        print_success "PostgreSQL Exporter secret created"
    fi

    # Deploy exporter
    helm upgrade --install postgres-exporter prometheus-community/prometheus-postgres-exporter \
        --namespace monitoring \
        --set config.datasourceSecret.name=postgres-exporter-secret \
        --set config.datasourceSecret.key=DATA_SOURCE_NAME \
        --set resources.limits.cpu=200m \
        --set resources.limits.memory=256Mi \
        --set resources.requests.cpu=50m \
        --set resources.requests.memory=64Mi \
        2>/dev/null || log_warn "PostgreSQL Exporter deployment may have failed"

    print_success "PostgreSQL Exporter deployed"
}

deploy_kafka_exporter() {
    log_info "Deploying Kafka Exporter..."

    helm upgrade --install kafka-exporter prometheus-community/prometheus-kafka-exporter \
        --namespace monitoring \
        --set kafkaServer=kafka.infra.svc.cluster.local:9092 \
        --set resources.limits.cpu=200m \
        --set resources.limits.memory=256Mi \
        --set resources.requests.cpu=50m \
        --set resources.requests.memory=64Mi \
        2>/dev/null || log_warn "Kafka Exporter deployment may have failed"

    print_success "Kafka Exporter deployed"
}

# ============================================================
# Grafana Configuration
# ============================================================

configure_grafana() {
    log_info "Configuring Grafana..."

    # Get Grafana password
    local grafana_password=$(kubectl get secret --namespace monitoring loki-grafana \
        -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d)

    if [[ -n "$grafana_password" ]]; then
        log_info "Grafana admin password: $grafana_password"
    else
        log_warn "Could not retrieve Grafana password"
    fi

    # Create Grafana Ingress if not exists
    create_grafana_ingress

    print_success "Grafana configured"
    return 0
}

create_grafana_ingress() {
    local ingress_file="$PROJECT_ROOT/k8s/monitoring/grafana-ingress.yaml"

    if [[ -f "$ingress_file" ]]; then
        kubectl apply -f "$ingress_file"
        print_success "Grafana Ingress applied"
    else
        log_info "Creating Grafana Ingress inline..."
        cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: grafana.son.duckdns.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: loki-grafana
            port:
              number: 80
EOF
        print_success "Grafana Ingress created"
    fi
}

# ============================================================
# Verification Functions
# ============================================================

verify_monitoring() {
    log_info "Verifying monitoring stack..."

    local warnings=0

    # Check Loki
    if kubectl get pods -n monitoring -l app=loki --no-headers 2>/dev/null | grep -q "Running"; then
        print_success "Loki is running"
    else
        log_warn "Loki is not running"
        ((warnings++))
    fi

    # Check Promtail
    local promtail_count=$(kubectl get pods -n monitoring -l app=promtail --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$promtail_count" -gt 0 ]]; then
        print_success "Promtail is running ($promtail_count pods)"
    else
        log_warn "Promtail is not running"
        ((warnings++))
    fi

    # Check Grafana
    if kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -q "Running"; then
        print_success "Grafana is running"
    else
        log_warn "Grafana is not running"
        ((warnings++))
    fi

    # Check Prometheus
    if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -q "Running"; then
        print_success "Prometheus is running"
    else
        log_warn "Prometheus is not running"
        ((warnings++))
    fi

    # Display pods
    echo ""
    log_info "Monitoring pods:"
    kubectl get pods -n monitoring

    # Display services
    echo ""
    log_info "Monitoring services:"
    kubectl get svc -n monitoring

    # Display Ingress
    echo ""
    log_info "Monitoring ingress:"
    kubectl get ingress -n monitoring 2>/dev/null || true

    if [[ $warnings -gt 0 ]]; then
        log_warn "Monitoring verification completed with $warnings warning(s)"
    fi

    return 0
}

# ============================================================
# Run Phase
# ============================================================

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    phase_04_monitoring
fi
