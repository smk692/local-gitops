#!/bin/bash

# ============================================================
# Phase 6: TLS/Certificate Management
# Deploys cert-manager and configures TLS certificates
# ============================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source libraries
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/validation.sh"

# ============================================================
# Phase 6 Main Function
# ============================================================

phase_06_tls() {
    print_header "Phase 6: TLS/Certificate Management"

    # Validate prerequisites
    print_step "6.0" "Prerequisites Check"
    validate_kubectl || return 1

    # Step 6.1: Install cert-manager
    print_step "6.1" "cert-manager Installation"
    install_cert_manager || return 1

    # Step 6.2: Configure ClusterIssuers
    print_step "6.2" "ClusterIssuer Configuration"
    configure_cluster_issuers || return 1

    # Step 6.3: Create Certificates
    print_step "6.3" "Certificate Creation"
    create_certificates || return 1

    # Step 6.4: Update Ingress for TLS
    print_step "6.4" "Ingress TLS Configuration"
    update_ingress_tls || return 1

    # Step 6.5: Verify TLS
    print_step "6.5" "TLS Verification"
    verify_tls || return 1

    log_success "Phase 6 completed successfully"
    return 0
}

# ============================================================
# cert-manager Installation
# ============================================================

install_cert_manager() {
    local values_file="$PROJECT_ROOT/helm/cert-manager-values.yaml"

    log_info "Installing cert-manager..."

    # Add Jetstack Helm repository
    if ! helm repo list | grep -q "^jetstack"; then
        helm repo add jetstack https://charts.jetstack.io
        helm repo update
    fi

    # Check if already deployed
    if helm status cert-manager -n cert-manager &>/dev/null; then
        log_info "cert-manager already deployed, checking for upgrade..."
    fi

    # Create namespace
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -

    # Build helm command
    local helm_args=(
        "upgrade" "--install" "cert-manager" "jetstack/cert-manager"
        "--namespace" "cert-manager"
        "--set" "installCRDs=true"
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

    # Wait for cert-manager to be ready
    log_info "Waiting for cert-manager to be ready..."
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=cert-manager \
        --timeout=300s

    print_success "cert-manager installed"
    return 0
}

# ============================================================
# ClusterIssuer Configuration
# ============================================================

configure_cluster_issuers() {
    local issuer_file="$PROJECT_ROOT/k8s/cert-manager/cluster-issuer.yaml"

    log_info "Configuring ClusterIssuers..."

    if [[ -f "$issuer_file" ]]; then
        # Wait a bit for cert-manager webhook to be ready
        sleep 10

        kubectl apply -f "$issuer_file"
        print_success "ClusterIssuers configured"
    else
        log_warn "ClusterIssuer file not found: $issuer_file"
        log_info "Creating default ClusterIssuers..."
        create_default_issuers
    fi

    return 0
}

create_default_issuers() {
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: admin@son.duckdns.org
    privateKeySecretRef:
      name: letsencrypt-staging-key
    solvers:
      - http01:
          ingress:
            class: nginx
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@son.duckdns.org
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
    print_success "Default ClusterIssuers created"
}

# ============================================================
# Certificate Creation
# ============================================================

create_certificates() {
    local cert_file="$PROJECT_ROOT/k8s/cert-manager/certificates.yaml"

    log_info "Creating certificates..."

    if [[ -f "$cert_file" ]]; then
        kubectl apply -f "$cert_file"
        print_success "Certificates created"
    else
        log_info "Certificate file not found, skipping..."
        log_info "Certificates will be auto-created by ingress annotations"
    fi

    return 0
}

# ============================================================
# Ingress TLS Update
# ============================================================

update_ingress_tls() {
    log_info "Updating Ingress resources for TLS..."

    # Update Grafana Ingress
    update_grafana_ingress_tls

    # Update Kafka UI Ingress
    update_kafka_ui_ingress_tls

    # Update other ingresses
    update_other_ingress_tls

    print_success "Ingress TLS configuration updated"
    return 0
}

update_grafana_ingress_tls() {
    # Check if Grafana ingress exists
    if ! kubectl get ingress grafana-ingress -n monitoring &>/dev/null; then
        log_info "Grafana ingress not found, skipping TLS update"
        return 0
    fi

    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - grafana.son.duckdns.org
      secretName: grafana-tls
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
    log_info "Grafana Ingress TLS updated"
}

update_kafka_ui_ingress_tls() {
    # Check if Kafka UI ingress exists
    if ! kubectl get ingress kafka-ui-ingress -n infra &>/dev/null; then
        log_info "Kafka UI ingress not found, creating with TLS..."
    fi

    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kafka-ui-ingress
  namespace: infra
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - kafka-ui.son.duckdns.org
      secretName: kafka-ui-tls
  rules:
    - host: kafka-ui.son.duckdns.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: kafka-ui
                port:
                  number: 8080
EOF
    log_info "Kafka UI Ingress TLS updated"
}

update_other_ingress_tls() {
    # pgAdmin TLS Ingress
    if kubectl get svc pgadmin -n database &>/dev/null; then
        cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pgadmin-ingress
  namespace: database
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - pgadmin.son.duckdns.org
      secretName: pgadmin-tls
  rules:
    - host: pgadmin.son.duckdns.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: pgadmin
                port:
                  number: 80
EOF
        log_info "pgAdmin Ingress TLS updated"
    fi
}

# ============================================================
# Verification
# ============================================================

verify_tls() {
    log_info "Verifying TLS configuration..."

    local warnings=0

    # Check cert-manager pods
    if kubectl get pods -n cert-manager --no-headers 2>/dev/null | grep -q "Running"; then
        print_success "cert-manager pods are running"
    else
        log_warn "cert-manager pods may not be ready"
        ((warnings++))
    fi

    # Check ClusterIssuers
    local issuers=$(kubectl get clusterissuer --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$issuers" -gt 0 ]]; then
        print_success "ClusterIssuers configured: $issuers"
    else
        log_warn "No ClusterIssuers found"
        ((warnings++))
    fi

    # Check Certificates
    local certs=$(kubectl get certificate --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$certs" -gt 0 ]]; then
        print_success "Certificates created: $certs"
    else
        log_info "No certificates created yet (will be auto-created by ingress)"
    fi

    # Display resources
    echo ""
    log_info "cert-manager pods:"
    kubectl get pods -n cert-manager

    echo ""
    log_info "ClusterIssuers:"
    kubectl get clusterissuer

    echo ""
    log_info "Certificates:"
    kubectl get certificate --all-namespaces

    echo ""
    log_info "TLS-enabled Ingresses:"
    kubectl get ingress --all-namespaces -o wide

    if [[ $warnings -gt 0 ]]; then
        log_warn "TLS verification completed with $warnings warning(s)"
    fi

    return 0
}

# ============================================================
# Run Phase
# ============================================================

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    phase_06_tls
fi
