#!/bin/bash

# ============================================================
# Validation Library - Pre-flight checks and validation functions
# ============================================================

# Prevent multiple sourcing
[[ -n "$_VALIDATION_SH_LOADED" ]] && return
_VALIDATION_SH_LOADED=1

# ============================================================
# Pre-flight Check Functions
# ============================================================

# Check all required CLI tools
check_required_tools() {
    local missing=()
    local tools=("kubectl" "helm" "k3d" "curl")

    for tool in "${tools[@]}"; do
        if ! command_exists "$tool"; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Install with: brew install ${missing[*]}"
        return 1
    fi

    log_success "All required tools are installed"
    return 0
}

# Check macOS version
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log_error "This script is designed for macOS"
        return 1
    fi

    local macos_version=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    log_info "macOS version: $macos_version"
    return 0
}

# Check Docker is running
check_docker() {
    if ! docker info &>/dev/null; then
        log_error "Docker is not running. Please start Docker Desktop."
        return 1
    fi

    log_success "Docker is running"
    return 0
}

# Check available disk space
check_disk_space() {
    local min_gb="${1:-20}"
    local available_gb

    if [[ "$OSTYPE" == "darwin"* ]]; then
        available_gb=$(df -g / | awk 'NR==2 {print $4}')
    else
        available_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')
    fi

    if [[ "$available_gb" -lt "$min_gb" ]]; then
        log_error "Insufficient disk space: ${available_gb}GB available, ${min_gb}GB required"
        return 1
    fi

    log_success "Disk space OK: ${available_gb}GB available"
    return 0
}

# Check available memory
check_memory() {
    local min_gb="${1:-8}"
    local total_gb

    if [[ "$OSTYPE" == "darwin"* ]]; then
        total_gb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
    else
        total_gb=$(free -g | awk '/^Mem:/{print $2}')
    fi

    if [[ "$total_gb" -lt "$min_gb" ]]; then
        log_warn "Low memory: ${total_gb}GB available, ${min_gb}GB recommended"
        return 0  # Warning only, don't fail
    fi

    log_success "Memory OK: ${total_gb}GB available"
    return 0
}

# ============================================================
# Kubernetes Validation Functions
# ============================================================

# Validate kubectl connection
validate_kubectl() {
    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi

    local context=$(kubectl config current-context 2>/dev/null || echo "none")
    log_success "Connected to cluster: $context"
    return 0
}

# Validate namespace exists
validate_namespace() {
    local namespace="$1"

    if ! kubectl get namespace "$namespace" &>/dev/null; then
        log_error "Namespace '$namespace' does not exist"
        return 1
    fi

    return 0
}

# Validate Helm release exists
validate_helm_release() {
    local release="$1"
    local namespace="${2:-default}"

    if ! helm status "$release" -n "$namespace" &>/dev/null; then
        log_warn "Helm release '$release' not found in namespace '$namespace'"
        return 1
    fi

    return 0
}

# ============================================================
# Service Validation Functions
# ============================================================

# Validate service has endpoints
validate_service_endpoints() {
    local service="$1"
    local namespace="${2:-default}"

    local endpoints=$(kubectl get endpoints "$service" -n "$namespace" \
        -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)

    if [[ -z "$endpoints" ]]; then
        log_warn "Service '$service' has no endpoints"
        return 1
    fi

    return 0
}

# Validate pod is running
validate_pod_running() {
    local label="$1"
    local namespace="${2:-default}"

    local running=$(kubectl get pods -n "$namespace" -l "$label" \
        --no-headers 2>/dev/null | grep -c "Running" || echo "0")

    if [[ "$running" -eq 0 ]]; then
        log_error "No running pods with label '$label' in namespace '$namespace'"
        return 1
    fi

    return 0
}

# Validate deployment is ready
validate_deployment_ready() {
    local deployment="$1"
    local namespace="${2:-default}"

    local status=$(kubectl get deployment "$deployment" -n "$namespace" \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)

    if [[ "$status" != "True" ]]; then
        log_error "Deployment '$deployment' is not ready"
        return 1
    fi

    return 0
}

# ============================================================
# Comprehensive Validation Functions
# ============================================================

# Run all pre-flight checks
run_preflight_checks() {
    print_header "Pre-flight Checks"

    local failed=0

    check_macos || ((failed++))
    check_required_tools || ((failed++))
    check_docker || ((failed++))
    check_disk_space 20 || ((failed++))
    check_memory 8 || true  # Memory is a warning only

    if [[ $failed -gt 0 ]]; then
        log_error "Pre-flight checks failed: $failed error(s)"
        return 1
    fi

    log_success "All pre-flight checks passed"
    return 0
}

# Validate infrastructure stack
validate_infrastructure() {
    print_header "Infrastructure Validation"

    local warnings=0
    local errors=0

    # Kubernetes connection
    if ! validate_kubectl; then
        ((errors++))
        return 1
    fi

    # Required namespaces
    local namespaces=("infra" "database" "monitoring")
    for ns in "${namespaces[@]}"; do
        if ! validate_namespace "$ns"; then
            ((warnings++))
        fi
    done

    # Ingress controller
    if ! validate_pod_running "app.kubernetes.io/component=controller" "kube-system"; then
        log_error "Ingress controller is not running"
        ((errors++))
    else
        log_success "Ingress controller is running"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Infrastructure validation failed: $errors error(s), $warnings warning(s)"
        return 1
    fi

    log_success "Infrastructure validation passed with $warnings warning(s)"
    return 0
}

# Validate service stack (Kafka, PostgreSQL, etc.)
validate_services() {
    print_header "Service Validation"

    local warnings=0

    # Kafka
    if validate_pod_running "app.kubernetes.io/name=kafka" "infra"; then
        log_success "Kafka is running"
    else
        ((warnings++))
    fi

    # PostgreSQL
    if validate_pod_running "app.kubernetes.io/name=postgresql" "database" 2>/dev/null || \
       kubectl get pods -n database --no-headers 2>/dev/null | grep -q "postgresql"; then
        log_success "PostgreSQL is running"
    else
        ((warnings++))
    fi

    # Monitoring
    if validate_pod_running "app=loki" "monitoring"; then
        log_success "Loki is running"
    else
        ((warnings++))
    fi

    if validate_pod_running "app.kubernetes.io/name=prometheus" "monitoring" 2>/dev/null; then
        log_success "Prometheus is running"
    else
        ((warnings++))
    fi

    if [[ $warnings -gt 0 ]]; then
        log_warn "Service validation completed with $warnings warning(s)"
    else
        log_success "All services are running"
    fi

    return 0
}

# ============================================================
# File Validation Functions
# ============================================================

# Validate required files exist
validate_required_files() {
    local missing=()

    local files=(
        "$PROJECT_ROOT/k3d/k3d-config.yaml"
        "$PROJECT_ROOT/helm/kafka-values.yaml"
        "$PROJECT_ROOT/helm/ingress-nginx-values.yaml"
        "$PROJECT_ROOT/k8s/namespaces/namespaces.yaml"
    )

    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing+=("$file")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing configuration files:"
        for file in "${missing[@]}"; do
            echo "  - $file"
        done
        return 1
    fi

    log_success "All required configuration files present"
    return 0
}

# ============================================================
# Export Functions
# ============================================================

export -f check_required_tools check_macos check_docker
export -f check_disk_space check_memory
export -f validate_kubectl validate_namespace validate_helm_release
export -f validate_service_endpoints validate_pod_running validate_deployment_ready
export -f run_preflight_checks validate_infrastructure validate_services
export -f validate_required_files
