#!/bin/bash

# ============================================================
# Phase 2: Infrastructure Services
# Deploys Kafka, Kafka UI, and other infrastructure components
# ============================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source libraries
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/validation.sh"

# ============================================================
# Phase 2 Main Function
# ============================================================

phase_02_infra() {
    print_header "Phase 2: Infrastructure Services"

    # Validate prerequisites
    print_step "2.0" "Prerequisites Check"
    validate_kubectl || return 1
    validate_namespace "infra" || {
        log_info "Creating infra namespace..."
        kubectl create namespace infra
    }

    # Step 2.1: Deploy Kafka
    print_step "2.1" "Kafka Deployment"
    deploy_kafka || return 1

    # Step 2.2: Deploy Kafka UI
    print_step "2.2" "Kafka UI Deployment"
    deploy_kafka_ui || return 1

    # Step 2.3: Verify infrastructure
    print_step "2.3" "Infrastructure Verification"
    verify_infra || return 1

    log_success "Phase 2 completed successfully"
    return 0
}

# ============================================================
# Kafka Functions
# ============================================================

deploy_kafka() {
    local values_file="$PROJECT_ROOT/helm/kafka-values.yaml"
    local profile_file="$PROJECT_ROOT/helm/profiles/$(get_resource_profile)-profile.yaml"

    log_info "Deploying Kafka (KRaft mode)..."

    # Check if already deployed
    if helm status kafka -n infra &>/dev/null; then
        log_info "Kafka already deployed, checking if upgrade needed..."
    fi

    # Build helm command
    local helm_args=(
        "upgrade" "--install" "kafka" "bitnami/kafka"
        "--version" "31.5.0"
        "--namespace" "infra"
        "--wait"
        "--timeout" "15m"
    )

    # Add values files if they exist
    if [[ -f "$values_file" ]]; then
        helm_args+=("--values" "$values_file")
    else
        log_warn "Kafka values file not found: $values_file"
    fi

    if [[ -f "$profile_file" ]]; then
        helm_args+=("--values" "$profile_file")
        log_info "Using resource profile: $(get_resource_profile)"
    fi

    # Deploy
    helm "${helm_args[@]}"

    # Wait for Kafka to be ready
    log_info "Waiting for Kafka to be ready..."
    kubectl wait --namespace infra \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=kafka \
        --timeout=600s

    print_success "Kafka deployed successfully"

    # Test Kafka
    test_kafka_connection

    return 0
}

test_kafka_connection() {
    log_info "Testing Kafka connection..."

    # Check if broker is responding
    if kubectl exec -n infra kafka-controller-0 -- \
        kafka-broker-api-versions.sh --bootstrap-server localhost:9092 &>/dev/null; then
        print_success "Kafka broker is responding"
    else
        log_warn "Kafka broker may not be fully ready"
    fi

    # List topics
    log_info "Existing topics:"
    kubectl exec -n infra kafka-controller-0 -- \
        kafka-topics.sh --list --bootstrap-server localhost:9092 2>/dev/null || true
}

# ============================================================
# Kafka UI Functions
# ============================================================

deploy_kafka_ui() {
    local kafka_ui_file="$PROJECT_ROOT/k8s/kafka/kafka-ui.yaml"

    log_info "Deploying Kafka UI..."

    if [[ -f "$kafka_ui_file" ]]; then
        kubectl apply -f "$kafka_ui_file"
    else
        log_warn "Kafka UI manifest not found, deploying inline..."
        deploy_kafka_ui_inline
    fi

    # Wait for Kafka UI to be ready
    log_info "Waiting for Kafka UI to be ready..."
    kubectl wait --namespace infra \
        --for=condition=ready pod \
        --selector=app=kafka-ui \
        --timeout=120s 2>/dev/null || log_warn "Kafka UI may not be fully ready"

    print_success "Kafka UI deployed"
    return 0
}

deploy_kafka_ui_inline() {
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kafka-ui
  namespace: infra
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kafka-ui
  template:
    metadata:
      labels:
        app: kafka-ui
    spec:
      containers:
      - name: kafka-ui
        image: provectuslabs/kafka-ui:latest
        ports:
        - containerPort: 8080
        env:
        - name: KAFKA_CLUSTERS_0_NAME
          value: "macmini-cluster"
        - name: KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS
          value: "kafka.infra.svc.cluster.local:9092"
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: kafka-ui
  namespace: infra
spec:
  selector:
    app: kafka-ui
  ports:
  - port: 8080
    targetPort: 8080
EOF
}

# ============================================================
# Verification Functions
# ============================================================

verify_infra() {
    log_info "Verifying infrastructure services..."

    local errors=0

    # Check Kafka
    if kubectl get pods -n infra -l app.kubernetes.io/name=kafka --no-headers | grep -q "Running"; then
        print_success "Kafka is running"
    else
        log_error "Kafka is not running"
        ((errors++))
    fi

    # Check Kafka UI
    if kubectl get pods -n infra -l app=kafka-ui --no-headers | grep -q "Running"; then
        print_success "Kafka UI is running"
    else
        log_warn "Kafka UI is not running"
    fi

    # Display pods
    echo ""
    log_info "Infrastructure pods:"
    kubectl get pods -n infra

    # Display services
    echo ""
    log_info "Infrastructure services:"
    kubectl get svc -n infra

    if [[ $errors -gt 0 ]]; then
        return 1
    fi

    return 0
}

# ============================================================
# Run Phase
# ============================================================

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    phase_02_infra
fi
