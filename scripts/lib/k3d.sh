#!/bin/bash

# ============================================================
# K3D Library - k3d cluster management functions
# ============================================================

# Prevent multiple sourcing
[[ -n "$_K3D_SH_LOADED" ]] && return
_K3D_SH_LOADED=1

# ============================================================
# K3D Cluster Functions
# ============================================================

# Check if k3d is installed
k3d_installed() {
    command_exists k3d
}

# Check if cluster exists
k3d_cluster_exists() {
    local cluster_name="${1:-macmini-cluster}"
    k3d cluster list 2>/dev/null | grep -q "$cluster_name"
}

# Check if cluster is running
k3d_cluster_running() {
    local cluster_name="${1:-macmini-cluster}"
    k3d cluster list 2>/dev/null | grep "$cluster_name" | grep -q "1/1"
}

# Create cluster from config
k3d_create_cluster() {
    local config_file="${1:-$PROJECT_ROOT/k3d/k3d-config.yaml}"
    local cluster_name="${2:-macmini-cluster}"

    if k3d_cluster_exists "$cluster_name"; then
        log_warn "Cluster '$cluster_name' already exists"
        return 0
    fi

    log_info "Creating k3d cluster from config: $config_file"

    if [[ -f "$config_file" ]]; then
        k3d cluster create --config "$config_file"
    else
        log_error "Config file not found: $config_file"
        return 1
    fi
}

# Delete cluster
k3d_delete_cluster() {
    local cluster_name="${1:-macmini-cluster}"

    if k3d_cluster_exists "$cluster_name"; then
        log_info "Deleting cluster '$cluster_name'..."
        k3d cluster delete "$cluster_name"
    else
        log_warn "Cluster '$cluster_name' does not exist"
    fi
}

# Start cluster
k3d_start_cluster() {
    local cluster_name="${1:-macmini-cluster}"

    if k3d_cluster_exists "$cluster_name"; then
        log_info "Starting cluster '$cluster_name'..."
        k3d cluster start "$cluster_name"
    else
        log_error "Cluster '$cluster_name' does not exist"
        return 1
    fi
}

# Stop cluster
k3d_stop_cluster() {
    local cluster_name="${1:-macmini-cluster}"

    if k3d_cluster_exists "$cluster_name"; then
        log_info "Stopping cluster '$cluster_name'..."
        k3d cluster stop "$cluster_name"
    else
        log_error "Cluster '$cluster_name' does not exist"
        return 1
    fi
}

# Get cluster kubeconfig
k3d_get_kubeconfig() {
    local cluster_name="${1:-macmini-cluster}"
    k3d kubeconfig get "$cluster_name"
}

# Switch kubectl context to cluster
k3d_use_context() {
    local cluster_name="${1:-macmini-cluster}"
    kubectl config use-context "k3d-$cluster_name"
}

# ============================================================
# K3D Health Check Functions
# ============================================================

# Check cluster health
k3d_health_check() {
    local cluster_name="${1:-macmini-cluster}"

    if ! k3d_installed; then
        log_error "k3d is not installed"
        return 1
    fi

    if ! k3d_cluster_exists "$cluster_name"; then
        log_error "Cluster '$cluster_name' does not exist"
        return 1
    fi

    if ! k3d_cluster_running "$cluster_name"; then
        log_error "Cluster '$cluster_name' is not running"
        return 1
    fi

    # Check kubectl connectivity
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to cluster via kubectl"
        return 1
    fi

    log_success "Cluster '$cluster_name' is healthy"
    return 0
}

# ============================================================
# K3D Setup Functions
# ============================================================

# Full k3d setup (create cluster, wait, configure)
k3d_full_setup() {
    local config_file="${1:-$PROJECT_ROOT/k3d/k3d-config.yaml}"
    local cluster_name="${2:-macmini-cluster}"

    print_step "1" "K3D Cluster Setup"

    # Check if k3d is installed
    if ! k3d_installed; then
        log_error "k3d is not installed. Please run: brew install k3d"
        return 1
    fi
    print_success "k3d is installed"

    # Create storage directory
    local storage_dir="$HOME/.k3d/storage"
    mkdir -p "$storage_dir"
    print_success "Storage directory ready: $storage_dir"

    # Create or use existing cluster
    if k3d_cluster_exists "$cluster_name"; then
        log_info "Cluster '$cluster_name' already exists"

        if ! k3d_cluster_running "$cluster_name"; then
            log_info "Starting stopped cluster..."
            k3d_start_cluster "$cluster_name"
        fi
    else
        log_info "Creating new cluster..."
        k3d_create_cluster "$config_file" "$cluster_name"
    fi

    # Wait for cluster to be ready
    log_info "Waiting for cluster to be ready..."
    sleep 5
    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    print_success "Cluster is ready"

    # Set context
    k3d_use_context "$cluster_name"
    print_success "kubectl context set to k3d-$cluster_name"

    return 0
}

# ============================================================
# K3D Port Information
# ============================================================

# Get cluster port mappings
k3d_get_ports() {
    local cluster_name="${1:-macmini-cluster}"
    echo "Port Mappings for $cluster_name:"
    echo "  HTTP:  localhost:8080 → cluster:80"
    echo "  HTTPS: localhost:8443 → cluster:443"
    echo "  API:   localhost:6550 → cluster:6443"
}

# ============================================================
# Export Functions
# ============================================================

export -f k3d_installed k3d_cluster_exists k3d_cluster_running
export -f k3d_create_cluster k3d_delete_cluster
export -f k3d_start_cluster k3d_stop_cluster
export -f k3d_get_kubeconfig k3d_use_context
export -f k3d_health_check k3d_full_setup k3d_get_ports
