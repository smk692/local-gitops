#!/bin/bash

# ============================================================
# Phase 5: Application Deployment
# Deploys Backend, Frontend, and Ingress configurations
# ============================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source libraries
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/validation.sh"

# ============================================================
# Phase 5 Main Function
# ============================================================

phase_05_apps() {
    print_header "Phase 5: Application Deployment"

    # Validate prerequisites
    print_step "5.0" "Prerequisites Check"
    validate_kubectl || return 1

    # Step 5.1: Create app namespaces
    print_step "5.1" "App Namespaces"
    create_app_namespaces || return 1

    # Step 5.2: Deploy Backend
    print_step "5.2" "Backend Deployment"
    deploy_backend || return 1

    # Step 5.3: Deploy Frontend
    print_step "5.3" "Frontend Deployment"
    deploy_frontend || return 1

    # Step 5.4: Configure Ingress Routes
    print_step "5.4" "Ingress Configuration"
    configure_app_ingress || return 1

    # Step 5.5: Verify applications
    print_step "5.5" "Application Verification"
    verify_apps || return 1

    log_success "Phase 5 completed successfully"
    return 0
}

# ============================================================
# Namespace Functions
# ============================================================

create_app_namespaces() {
    local namespaces=("backend" "frontend")

    for ns in "${namespaces[@]}"; do
        if ! namespace_exists "$ns"; then
            log_info "Creating $ns namespace..."
            kubectl create namespace "$ns"
        fi
    done

    print_success "App namespaces ready"
    return 0
}

# ============================================================
# Backend Functions
# ============================================================

deploy_backend() {
    local backend_dir="$PROJECT_ROOT/k8s/backend"

    log_info "Deploying Backend services..."

    if [[ -d "$backend_dir" ]] && [[ -n "$(ls -A "$backend_dir" 2>/dev/null)" ]]; then
        kubectl apply -f "$backend_dir/" -n backend
        print_success "Backend manifests applied"

        # Wait for backend to be ready
        log_info "Waiting for Backend to be ready..."
        kubectl wait --namespace backend \
            --for=condition=ready pod \
            --selector=app=backend \
            --timeout=180s 2>/dev/null || log_warn "Backend may not be fully ready"
    else
        log_info "No backend manifests found at $backend_dir"
        log_info "Skipping backend deployment (add manifests to deploy)"
    fi

    return 0
}

# ============================================================
# Frontend Functions
# ============================================================

deploy_frontend() {
    local frontend_dir="$PROJECT_ROOT/k8s/frontend"

    log_info "Deploying Frontend services..."

    if [[ -d "$frontend_dir" ]] && [[ -n "$(ls -A "$frontend_dir" 2>/dev/null)" ]]; then
        kubectl apply -f "$frontend_dir/" -n frontend
        print_success "Frontend manifests applied"

        # Wait for frontend to be ready
        log_info "Waiting for Frontend to be ready..."
        kubectl wait --namespace frontend \
            --for=condition=ready pod \
            --selector=app=frontend \
            --timeout=180s 2>/dev/null || log_warn "Frontend may not be fully ready"
    else
        log_info "No frontend manifests found at $frontend_dir"
        log_info "Skipping frontend deployment (add manifests to deploy)"
    fi

    return 0
}

# ============================================================
# Ingress Functions
# ============================================================

configure_app_ingress() {
    local ingress_dir="$PROJECT_ROOT/k8s/ingress"

    log_info "Configuring application Ingress routes..."

    if [[ -d "$ingress_dir" ]] && [[ -n "$(ls -A "$ingress_dir" 2>/dev/null)" ]]; then
        kubectl apply -f "$ingress_dir/"
        print_success "Ingress manifests applied"
    else
        log_info "No ingress manifests found at $ingress_dir"
        log_info "Creating default application ingress..."
        create_default_app_ingress
    fi

    return 0
}

create_default_app_ingress() {
    # Only create if backend or frontend services exist
    local has_backend=$(kubectl get svc -n backend -o name 2>/dev/null | head -1)
    local has_frontend=$(kubectl get svc -n frontend -o name 2>/dev/null | head -1)

    if [[ -z "$has_backend" ]] && [[ -z "$has_frontend" ]]; then
        log_info "No application services found, skipping ingress creation"
        return 0
    fi

    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: frontend
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /\$2
spec:
  ingressClassName: nginx
  rules:
  - host: app.son.duckdns.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
      - path: /api(/|$)(.*)
        pathType: ImplementationSpecific
        backend:
          service:
            name: backend.backend.svc.cluster.local
            port:
              number: 8080
EOF

    print_success "Default app ingress created"
}

# ============================================================
# Verification Functions
# ============================================================

verify_apps() {
    log_info "Verifying application deployment..."

    local warnings=0

    # Check Backend
    local backend_pods=$(kubectl get pods -n backend --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$backend_pods" -gt 0 ]]; then
        print_success "Backend is running ($backend_pods pods)"
    else
        log_info "No backend pods running (deploy backend manifests first)"
    fi

    # Check Frontend
    local frontend_pods=$(kubectl get pods -n frontend --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$frontend_pods" -gt 0 ]]; then
        print_success "Frontend is running ($frontend_pods pods)"
    else
        log_info "No frontend pods running (deploy frontend manifests first)"
    fi

    # Display pods
    echo ""
    log_info "Backend pods:"
    kubectl get pods -n backend 2>/dev/null || echo "  No resources"

    echo ""
    log_info "Frontend pods:"
    kubectl get pods -n frontend 2>/dev/null || echo "  No resources"

    # Display services
    echo ""
    log_info "Backend services:"
    kubectl get svc -n backend 2>/dev/null || echo "  No resources"

    echo ""
    log_info "Frontend services:"
    kubectl get svc -n frontend 2>/dev/null || echo "  No resources"

    # Display Ingress
    echo ""
    log_info "Application ingress:"
    kubectl get ingress -n frontend 2>/dev/null || true
    kubectl get ingress -n backend 2>/dev/null || true

    return 0
}

# ============================================================
# Run Phase
# ============================================================

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    phase_05_apps
fi
