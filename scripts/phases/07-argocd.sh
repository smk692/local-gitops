#!/bin/bash

# ============================================================
# Phase 7: ArgoCD GitOps Setup
# Deploys ArgoCD for GitOps continuous delivery
# ============================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Source libraries
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/validation.sh"

# ============================================================
# Phase 7 Main Function
# ============================================================

phase_07_argocd() {
    print_header "Phase 7: ArgoCD GitOps Setup"

    # Validate prerequisites
    print_step "7.0" "Prerequisites Check"
    validate_kubectl || return 1

    # Step 7.1: Create ArgoCD namespace
    print_step "7.1" "ArgoCD Namespace"
    create_argocd_namespace || return 1

    # Step 7.2: Install ArgoCD
    print_step "7.2" "ArgoCD Installation"
    install_argocd || return 1

    # Step 7.3: Configure ArgoCD
    print_step "7.3" "ArgoCD Configuration"
    configure_argocd || return 1

    # Step 7.4: Create ArgoCD Ingress
    print_step "7.4" "ArgoCD Ingress"
    create_argocd_ingress || return 1

    # Step 7.5: Get Admin Password
    print_step "7.5" "Admin Credentials"
    get_argocd_credentials || return 1

    # Step 7.6: Verify ArgoCD
    print_step "7.6" "ArgoCD Verification"
    verify_argocd || return 1

    log_success "Phase 7 completed successfully"
    return 0
}

# ============================================================
# Namespace
# ============================================================

create_argocd_namespace() {
    if ! namespace_exists "argocd"; then
        log_info "Creating argocd namespace..."
        kubectl create namespace argocd
    fi
    print_success "ArgoCD namespace ready"
    return 0
}

# ============================================================
# Installation
# ============================================================

install_argocd() {
    local values_file="$PROJECT_ROOT/helm/argocd-values.yaml"

    log_info "Installing ArgoCD..."

    # Add Argo Helm repository
    if ! helm repo list | grep -q "^argo"; then
        helm repo add argo https://argoproj.github.io/argo-helm
        helm repo update
    fi

    # Check if already deployed
    if helm status argocd -n argocd &>/dev/null; then
        log_info "ArgoCD already deployed, checking for upgrade..."
    fi

    # Build helm command
    local helm_args=(
        "upgrade" "--install" "argocd" "argo/argo-cd"
        "--namespace" "argocd"
        "--wait"
        "--timeout" "10m"
    )

    # Add values file if exists
    if [[ -f "$values_file" ]]; then
        helm_args+=("--values" "$values_file")
        log_info "Using values file: $values_file"
    else
        # Default minimal configuration
        helm_args+=(
            "--set" "server.extraArgs={--insecure}"
            "--set" "dex.enabled=false"
        )
    fi

    # Deploy
    helm "${helm_args[@]}"

    # Wait for ArgoCD to be ready
    log_info "Waiting for ArgoCD to be ready..."
    kubectl wait --namespace argocd \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=argocd-server \
        --timeout=300s

    print_success "ArgoCD installed"
    return 0
}

# ============================================================
# Configuration
# ============================================================

configure_argocd() {
    log_info "Configuring ArgoCD..."

    # Apply AppProjects
    local apps_dir="$PROJECT_ROOT/k8s/argocd/apps"

    if [[ -d "$apps_dir" ]]; then
        # Apply app configurations
        for app_file in "$apps_dir"/*.yaml; do
            if [[ -f "$app_file" ]]; then
                log_info "Applying: $(basename "$app_file")"
                kubectl apply -f "$app_file" 2>/dev/null || log_warn "May need to update repo URL in $app_file"
            fi
        done
    fi

    # Configure RBAC
    configure_argocd_rbac

    print_success "ArgoCD configured"
    return 0
}

configure_argocd_rbac() {
    log_info "Configuring ArgoCD RBAC..."

    # Create admin group ConfigMap
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-rbac-cm
    app.kubernetes.io/part-of: argocd
data:
  policy.default: role:readonly
  policy.csv: |
    g, argocd-admins, role:admin
    p, role:sync-only, applications, sync, */*, allow
    p, role:sync-only, applications, get, */*, allow
    g, developers, role:sync-only
EOF
}

# ============================================================
# Ingress
# ============================================================

create_argocd_ingress() {
    log_info "Creating ArgoCD Ingress..."

    # Check if ingress already exists from Helm
    if kubectl get ingress argocd-server -n argocd &>/dev/null; then
        log_info "ArgoCD Ingress already exists from Helm values"
        return 0
    fi

    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    cert-manager.io/cluster-issuer: "letsencrypt-staging"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - argocd.son.duckdns.org
      secretName: argocd-server-tls
  rules:
    - host: argocd.son.duckdns.org
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
EOF

    print_success "ArgoCD Ingress created"
    return 0
}

# ============================================================
# Credentials
# ============================================================

get_argocd_credentials() {
    log_info "Retrieving ArgoCD admin credentials..."

    # Get initial admin password
    local admin_password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

    if [[ -n "$admin_password" ]]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║                  ArgoCD Admin Credentials                     ║"
        echo "╠══════════════════════════════════════════════════════════════╣"
        echo "║                                                              ║"
        echo "║  URL:      https://argocd.son.duckdns.org:8443               ║"
        echo "║  Username: admin                                             ║"
        echo "║  Password: $admin_password"
        echo "║                                                              ║"
        echo "║  Change password after first login!                          ║"
        echo "║                                                              ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""

        # Save to secrets directory
        local secrets_dir="$PROJECT_ROOT/secrets"
        if [[ -d "$secrets_dir" ]]; then
            echo "ARGOCD_ADMIN_PASSWORD=$admin_password" >> "$secrets_dir/.env"
            log_info "ArgoCD password saved to secrets/.env"
        fi
    else
        log_warn "Could not retrieve ArgoCD admin password"
        log_info "Try: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
    fi

    print_success "ArgoCD credentials retrieved"
    return 0
}

# ============================================================
# Verification
# ============================================================

verify_argocd() {
    log_info "Verifying ArgoCD deployment..."

    local warnings=0

    # Check ArgoCD server
    if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server --no-headers 2>/dev/null | grep -q "Running"; then
        print_success "ArgoCD Server is running"
    else
        log_warn "ArgoCD Server may not be ready"
        ((warnings++))
    fi

    # Check ArgoCD controller
    if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller --no-headers 2>/dev/null | grep -q "Running"; then
        print_success "ArgoCD Controller is running"
    else
        log_warn "ArgoCD Controller may not be ready"
        ((warnings++))
    fi

    # Check ArgoCD repo server
    if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server --no-headers 2>/dev/null | grep -q "Running"; then
        print_success "ArgoCD Repo Server is running"
    else
        log_warn "ArgoCD Repo Server may not be ready"
        ((warnings++))
    fi

    # Display resources
    echo ""
    log_info "ArgoCD pods:"
    kubectl get pods -n argocd

    echo ""
    log_info "ArgoCD services:"
    kubectl get svc -n argocd

    echo ""
    log_info "ArgoCD ingress:"
    kubectl get ingress -n argocd

    echo ""
    log_info "ArgoCD Applications:"
    kubectl get applications -n argocd 2>/dev/null || echo "  No applications yet"

    echo ""
    log_info "ArgoCD AppProjects:"
    kubectl get appprojects -n argocd 2>/dev/null || echo "  Default project only"

    if [[ $warnings -gt 0 ]]; then
        log_warn "ArgoCD verification completed with $warnings warning(s)"
    fi

    return 0
}

# ============================================================
# CLI Setup Helper
# ============================================================

setup_argocd_cli() {
    log_info "Setting up ArgoCD CLI..."

    # Check if argocd CLI is installed
    if ! command -v argocd &>/dev/null; then
        log_info "Installing ArgoCD CLI..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            brew install argocd
        else
            curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
            chmod +x /usr/local/bin/argocd
        fi
    fi

    # Login to ArgoCD
    local admin_password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)

    if [[ -n "$admin_password" ]]; then
        # Port-forward for CLI access
        log_info "Setting up port-forward for CLI access..."
        kubectl port-forward svc/argocd-server -n argocd 8443:443 &
        sleep 3

        argocd login localhost:8443 --username admin --password "$admin_password" --insecure
        print_success "ArgoCD CLI configured"
    fi
}

# ============================================================
# Run Phase
# ============================================================

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    phase_07_argocd
fi
