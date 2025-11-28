#!/bin/bash

# ============================================================
# Phase 1: Cluster Setup
# Creates k3d cluster and installs ingress controller
# ============================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source libraries
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/k3d.sh"
source "$SCRIPT_DIR/../lib/validation.sh"

# ============================================================
# Phase 1 Main Function
# ============================================================

phase_01_cluster() {
    print_header "Phase 1: Cluster Setup"

    # Step 1.1: Pre-flight checks
    print_step "1.1" "Pre-flight Checks"
    run_preflight_checks || return 1

    # Step 1.2: K3D Cluster Setup
    print_step "1.2" "K3D Cluster"
    k3d_full_setup "$PROJECT_ROOT/k3d/k3d-config.yaml" "macmini-cluster" || return 1

    # Step 1.3: Add Helm repositories
    print_step "1.3" "Helm Repositories"
    setup_helm_repos || return 1

    # Step 1.4: Create namespaces
    print_step "1.4" "Kubernetes Namespaces"
    create_namespaces || return 1

    # Step 1.5: Install Ingress Controller
    print_step "1.5" "NGINX Ingress Controller"
    install_ingress_controller || return 1

    # Step 1.6: Verify cluster
    print_step "1.6" "Cluster Verification"
    verify_cluster || return 1

    log_success "Phase 1 completed successfully"
    return 0
}

# ============================================================
# Helper Functions
# ============================================================

setup_helm_repos() {
    local repos=(
        "bitnami:https://charts.bitnami.com/bitnami"
        "grafana:https://grafana.github.io/helm-charts"
        "ingress-nginx:https://kubernetes.github.io/ingress-nginx"
        "prometheus-community:https://prometheus-community.github.io/helm-charts"
        "jetstack:https://charts.jetstack.io"
        "argo:https://argoproj.github.io/argo-helm"
    )

    for repo in "${repos[@]}"; do
        local name="${repo%%:*}"
        local url="${repo#*:}"

        if ! helm repo list | grep -q "^$name"; then
            log_info "Adding Helm repo: $name"
            helm repo add "$name" "$url"
        else
            log_debug "Helm repo already exists: $name"
        fi
    done

    log_info "Updating Helm repositories..."
    helm repo update

    print_success "Helm repositories configured"
    return 0
}

create_namespaces() {
    local ns_file="$PROJECT_ROOT/k8s/namespaces/namespaces.yaml"

    if [[ -f "$ns_file" ]]; then
        kubectl apply -f "$ns_file"
        print_success "Namespaces created from $ns_file"
    else
        log_warn "Namespace file not found, creating manually..."
        local namespaces=("infra" "database" "backend" "frontend" "monitoring")
        for ns in "${namespaces[@]}"; do
            kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
        done
        print_success "Namespaces created"
    fi

    # List created namespaces
    kubectl get namespaces | grep -E "infra|database|backend|frontend|monitoring"

    return 0
}

install_ingress_controller() {
    local values_file="$PROJECT_ROOT/helm/ingress-nginx-values.yaml"

    log_info "Installing NGINX Ingress Controller..."

    if [[ -f "$values_file" ]]; then
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace kube-system \
            --values "$values_file" \
            --wait \
            --timeout 5m
    else
        log_warn "Values file not found, using defaults..."
        helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
            --namespace kube-system \
            --set controller.service.type=LoadBalancer \
            --set controller.service.ports.http=80 \
            --set controller.service.ports.https=443 \
            --wait \
            --timeout 5m
    fi

    # Wait for ingress controller to be ready
    log_info "Waiting for Ingress Controller to be ready..."
    kubectl wait --namespace kube-system \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s

    print_success "NGINX Ingress Controller installed"
    return 0
}

verify_cluster() {
    log_info "Verifying cluster setup..."

    # Check nodes
    local nodes_ready=$(kubectl get nodes --no-headers | grep -c "Ready")
    if [[ "$nodes_ready" -ge 1 ]]; then
        print_success "Nodes ready: $nodes_ready"
    else
        log_error "No nodes are ready"
        return 1
    fi

    # Check system pods
    local system_pods=$(kubectl get pods -n kube-system --no-headers | grep -c "Running")
    print_success "System pods running: $system_pods"

    # Check ingress
    if kubectl get pods -n kube-system -l app.kubernetes.io/component=controller --no-headers | grep -q "Running"; then
        print_success "Ingress controller is running"
    else
        log_warn "Ingress controller may not be ready"
    fi

    # Display cluster info
    echo ""
    log_info "Cluster Information:"
    kubectl cluster-info

    echo ""
    log_info "Nodes:"
    kubectl get nodes

    echo ""
    log_info "Namespaces:"
    kubectl get namespaces

    return 0
}

# ============================================================
# Run Phase
# ============================================================

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    phase_01_cluster
fi
