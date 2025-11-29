#!/bin/bash

# ============================================================
# Mac Mini Complete Infrastructure Deployment
# Modular, checkpoint-based, idempotent deployment
# Version: 1.1.0 (2025-11-28)
# ============================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/validation.sh"

# ============================================================
# Configuration
# ============================================================

# Deployment mode: full, resume, phase
DEPLOY_MODE="${DEPLOY_MODE:-full}"

# Skip confirmation prompt
SKIP_CONFIRM="${SKIP_CONFIRM:-false}"

# Specific phase to run (1-5)
RUN_PHASE="${RUN_PHASE:-}"

# ============================================================
# Usage
# ============================================================

show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Mac Mini Complete Infrastructure Deployment

Options:
  -h, --help          Show this help message
  -y, --yes           Skip confirmation prompts
  -r, --resume        Resume from last checkpoint
  -p, --phase NUM     Run specific phase only (1-5)
  -c, --clean         Clean deployment (remove checkpoints)
  --status            Show current deployment status
  --validate          Validate prerequisites only

Phases:
  1. Cluster Setup    (k3d, Helm repos, namespaces, ingress)
  2. Infrastructure   (Kafka, Kafka UI)
  3. Database         (PostgreSQL, pgAdmin, schemas)
  4. Monitoring       (Loki, Promtail, Grafana, Prometheus)
  5. Applications     (Backend, Frontend, Ingress routes)
  6. TLS              (cert-manager, Let's Encrypt certificates)
  7. ArgoCD           (GitOps continuous delivery)

Environment Variables:
  PROFILE             Resource profile: 8gb, 16gb, 32gb (default: auto-detect)
  DEPLOY_MODE         Deployment mode: full, resume, phase
  SKIP_CONFIRM        Skip confirmation: true, false
  RUN_PHASE           Specific phase number to run (1-7)
  ENABLE_TLS          Enable TLS phase: true, false (default: false)
  ENABLE_ARGOCD       Enable ArgoCD phase: true, false (default: false)

Examples:
  $0                  # Full deployment with confirmation
  $0 -y               # Full deployment without confirmation
  $0 -r               # Resume from last checkpoint
  $0 -p 2             # Run phase 2 only (Infrastructure)
  $0 -p 6             # Run phase 6 only (TLS)
  $0 --status         # Show deployment status
  $0 --validate       # Validate prerequisites only
  ENABLE_TLS=true ENABLE_ARGOCD=true $0 -y  # Full deployment with TLS and ArgoCD

EOF
}

# ============================================================
# Parse Arguments
# ============================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_usage
                exit 0
                ;;
            -y|--yes)
                SKIP_CONFIRM="true"
                shift
                ;;
            -r|--resume)
                DEPLOY_MODE="resume"
                shift
                ;;
            -p|--phase)
                DEPLOY_MODE="phase"
                RUN_PHASE="$2"
                shift 2
                ;;
            -c|--clean)
                rm -f "$CHECKPOINT_FILE" 2>/dev/null
                log_info "Checkpoints cleared"
                shift
                ;;
            --status)
                show_status
                exit 0
                ;;
            --validate)
                run_preflight_checks
                exit $?
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# ============================================================
# Status Display
# ============================================================

show_status() {
    print_header "Deployment Status"

    # Check cluster
    if k3d cluster list 2>/dev/null | grep -q "macmini-cluster"; then
        local cluster_status=$(k3d cluster list 2>/dev/null | grep "macmini-cluster" | awk '{print $2}')
        if [[ "$cluster_status" == "1/1" ]]; then
            print_success "Cluster: macmini-cluster (running)"
        else
            log_warn "Cluster: macmini-cluster ($cluster_status)"
        fi
    else
        log_error "Cluster: Not found"
    fi

    # Check namespaces
    echo ""
    log_info "Namespaces:"
    for ns in infra database backend frontend monitoring; do
        if kubectl get namespace "$ns" &>/dev/null; then
            local pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
            local running=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
            echo "  ✓ $ns: $running/$pods pods running"
        else
            echo "  ✗ $ns: not created"
        fi
    done

    # Check services
    echo ""
    log_info "Services:"

    # Kafka
    if kubectl get pods -n infra -l app.kubernetes.io/name=kafka --no-headers 2>/dev/null | grep -q "Running"; then
        print_success "  Kafka: Running"
    else
        log_warn "  Kafka: Not running"
    fi

    # PostgreSQL
    if kubectl get pods -n database --no-headers 2>/dev/null | grep -q "postgresql.*Running"; then
        print_success "  PostgreSQL: Running"
    else
        log_warn "  PostgreSQL: Not running"
    fi

    # Monitoring
    if kubectl get pods -n monitoring -l app=loki --no-headers 2>/dev/null | grep -q "Running"; then
        print_success "  Loki: Running"
    else
        log_warn "  Loki: Not running"
    fi

    if kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -q "Running"; then
        print_success "  Prometheus: Running"
    else
        log_warn "  Prometheus: Not running"
    fi

    # Checkpoints
    echo ""
    log_info "Checkpoints:"
    if [[ -f "$CHECKPOINT_FILE" ]]; then
        cat "$CHECKPOINT_FILE" | while read line; do
            echo "  ✓ $line"
        done
    else
        echo "  No checkpoints saved"
    fi

    # Resource usage
    echo ""
    log_info "Resource Usage:"
    kubectl top nodes 2>/dev/null || echo "  Metrics server not available"
}

# ============================================================
# Deployment Banner
# ============================================================

show_banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       Mac Mini M4 - Complete Infrastructure Deployment       ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║                                                              ║"
    echo "║  This script will deploy:                                    ║"
    echo "║    Phase 1: k3d Cluster + Ingress Controller                 ║"
    echo "║    Phase 2: Kafka (KRaft mode) + Kafka UI                    ║"
    echo "║    Phase 3: PostgreSQL + pgAdmin + Schemas                   ║"
    echo "║    Phase 4: Loki + Promtail + Grafana + Prometheus           ║"
    echo "║    Phase 5: Backend + Frontend + Ingress Routes              ║"
    echo "║                                                              ║"
    echo "║  Profile: $(get_resource_profile)                                             ║"
    echo "║  Mode: $DEPLOY_MODE                                              ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
}

# ============================================================
# Confirmation
# ============================================================

confirm_deployment() {
    if [[ "$SKIP_CONFIRM" == "true" ]]; then
        return 0
    fi

    echo -n "Continue with deployment? (y/n) "
    read -r response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            log_info "Deployment cancelled"
            exit 0
            ;;
    esac
}

# ============================================================
# Phase Execution
# ============================================================

run_phase() {
    local phase_num="$1"
    local phase_name="$2"
    local phase_script="$SCRIPT_DIR/phases/0${phase_num}-*.sh"

    # Check if should skip (already completed in resume mode)
    if [[ "$DEPLOY_MODE" == "resume" ]] && should_skip_phase "phase_${phase_num}"; then
        log_info "Skipping Phase $phase_num (already completed)"
        return 0
    fi

    # Find and source phase script
    local script_file=$(ls $phase_script 2>/dev/null | head -1)

    if [[ -z "$script_file" ]] || [[ ! -f "$script_file" ]]; then
        log_error "Phase $phase_num script not found"
        return 1
    fi

    # Source and run phase
    source "$script_file"

    local phase_func="phase_0${phase_num}_*"
    local func_name=$(declare -F | grep "phase_0${phase_num}" | awk '{print $3}' | head -1)

    if [[ -n "$func_name" ]]; then
        "$func_name" || {
            log_error "Phase $phase_num failed"
            return 1
        }
        save_checkpoint "phase_${phase_num}"
    else
        log_error "Phase function not found in $script_file"
        return 1
    fi
}

# ============================================================
# Main Deployment
# ============================================================

deploy_all() {
    local start_time=$(date +%s)

    # Initialize checkpoints
    init_checkpoint

    # Phase 1: Cluster Setup
    run_phase 1 "Cluster Setup" || return 1

    # Phase 2: Infrastructure
    run_phase 2 "Infrastructure" || return 1

    # Phase 3: Database
    run_phase 3 "Database" || return 1

    # Phase 4: Monitoring
    run_phase 4 "Monitoring" || return 1

    # Phase 5: Applications
    run_phase 5 "Applications" || return 1

    # Phase 6: TLS (optional)
    if [[ "${ENABLE_TLS:-false}" == "true" ]]; then
        run_phase 6 "TLS/Certificates" || log_warn "TLS setup failed, continuing..."
    fi

    # Phase 7: ArgoCD (optional)
    if [[ "${ENABLE_ARGOCD:-false}" == "true" ]]; then
        run_phase 7 "ArgoCD GitOps" || log_warn "ArgoCD setup failed, continuing..."
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    log_info "Total deployment time: ${duration}s"

    return 0
}

deploy_single_phase() {
    local phase="$1"

    if [[ -z "$phase" ]] || [[ ! "$phase" =~ ^[1-7]$ ]]; then
        log_error "Invalid phase number: $phase (must be 1-7)"
        return 1
    fi

    run_phase "$phase" "Phase $phase"
}

# ============================================================
# Summary
# ============================================================

show_summary() {
    print_header "Deployment Complete"

    echo ""
    log_info "Cluster Status:"
    kubectl get nodes

    echo ""
    log_info "All Pods:"
    kubectl get pods --all-namespaces | head -30

    echo ""
    log_info "Services:"
    kubectl get svc --all-namespaces | grep -E "kafka|postgresql|loki|grafana|prometheus|pgadmin"

    echo ""
    log_info "Ingress:"
    kubectl get ingress --all-namespaces

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                     Access Information                        ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║                                                              ║"
    echo "║  Add to /etc/hosts:                                          ║"
    echo "║    127.0.0.1  kafka-ui.son.duckdns.org                       ║"
    echo "║    127.0.0.1  pgadmin.son.duckdns.org                        ║"
    echo "║    127.0.0.1  grafana.son.duckdns.org                        ║"
    echo "║    127.0.0.1  app.son.duckdns.org                            ║"
    echo "║    127.0.0.1  api.son.duckdns.org                            ║"
    echo "║                                                              ║"
    echo "║  URLs (port 8080):                                           ║"
    echo "║    Kafka UI:  http://kafka-ui.son.duckdns.org:8080           ║"
    echo "║    pgAdmin:   http://pgadmin.son.duckdns.org:8080            ║"
    echo "║    Grafana:   http://grafana.son.duckdns.org:8080            ║"
    echo "║    Frontend:  http://app.son.duckdns.org:8080                ║"
    echo "║    Backend:   http://api.son.duckdns.org:8080/api            ║"
    echo "║                                                              ║"
    echo "║  Internal Endpoints:                                         ║"
    echo "║    Kafka:      kafka.infra.svc.cluster.local:9092            ║"
    echo "║    PostgreSQL: postgresql.database.svc.cluster.local:5432   ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""

    # Get passwords
    echo ""
    log_info "Credentials:"

    local grafana_pass=$(kubectl get secret --namespace monitoring loki-grafana \
        -o jsonpath="{.data.admin-password}" 2>/dev/null | base64 -d)
    if [[ -n "$grafana_pass" ]]; then
        echo "  Grafana: admin / $grafana_pass"
    fi

    echo "  pgAdmin: admin@local.dev / admin123"
    echo "  PostgreSQL: appuser / appuser123"
    echo ""

    log_success "Infrastructure deployment completed!"
}

# ============================================================
# Main Entry Point
# ============================================================

main() {
    parse_args "$@"

    show_banner

    # Run pre-flight checks
    if ! run_preflight_checks; then
        log_error "Pre-flight checks failed. Fix issues and retry."
        exit 1
    fi

    confirm_deployment

    # Execute based on mode
    case "$DEPLOY_MODE" in
        full|resume)
            if deploy_all; then
                show_summary
            else
                log_error "Deployment failed. Check logs and retry with --resume"
                exit 1
            fi
            ;;
        phase)
            if deploy_single_phase "$RUN_PHASE"; then
                log_success "Phase $RUN_PHASE completed successfully"
            else
                log_error "Phase $RUN_PHASE failed"
                exit 1
            fi
            ;;
    esac
}

# Run main
main "$@"
