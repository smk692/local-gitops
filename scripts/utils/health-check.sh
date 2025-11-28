#!/bin/bash

# ============================================================
# Mac Mini Infrastructure Health Check Script
# Comprehensive status check for all services
# ============================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output format (text or json)
OUTPUT_FORMAT="${1:-text}"

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Results array for JSON output
declare -a RESULTS

# ============================================================
# Helper Functions
# ============================================================

print_header() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}  $1${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    fi
}

check_pass() {
    ((TOTAL_CHECKS++))
    ((PASSED_CHECKS++))
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "  ${GREEN}✓${NC} $1"
    fi
    RESULTS+=("{\"check\":\"$1\",\"status\":\"pass\",\"details\":\"$2\"}")
}

check_fail() {
    ((TOTAL_CHECKS++))
    ((FAILED_CHECKS++))
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "  ${RED}✗${NC} $1"
        [[ -n "$2" ]] && echo -e "    ${RED}└─ $2${NC}"
    fi
    RESULTS+=("{\"check\":\"$1\",\"status\":\"fail\",\"details\":\"$2\"}")
}

check_warn() {
    ((TOTAL_CHECKS++))
    ((WARNING_CHECKS++))
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "  ${YELLOW}⚠${NC} $1"
        [[ -n "$2" ]] && echo -e "    ${YELLOW}└─ $2${NC}"
    fi
    RESULTS+=("{\"check\":\"$1\",\"status\":\"warning\",\"details\":\"$2\"}")
}

# ============================================================
# Check Functions
# ============================================================

check_k3d_cluster() {
    print_header "K3D Cluster Status"

    # Check if k3d is installed
    if ! command -v k3d &> /dev/null; then
        check_fail "k3d CLI" "k3d is not installed"
        return
    fi
    check_pass "k3d CLI installed"

    # Check if cluster exists
    if k3d cluster list 2>/dev/null | grep -q "macmini-cluster"; then
        check_pass "Cluster 'macmini-cluster' exists"
    else
        check_fail "Cluster 'macmini-cluster'" "Cluster not found"
        return
    fi

    # Check cluster running state
    if k3d cluster list 2>/dev/null | grep "macmini-cluster" | grep -q "1/1"; then
        check_pass "Cluster is running (1/1 nodes)"
    else
        check_fail "Cluster state" "Not all nodes are running"
    fi
}

check_kubectl_connection() {
    print_header "Kubernetes Connection"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        check_fail "kubectl CLI" "kubectl is not installed"
        return
    fi
    check_pass "kubectl CLI installed"

    # Check context
    CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
    if [[ "$CONTEXT" == "k3d-macmini-cluster" ]]; then
        check_pass "Current context: $CONTEXT"
    else
        check_warn "Current context" "Expected k3d-macmini-cluster, got $CONTEXT"
    fi

    # Check API connection
    if kubectl cluster-info &>/dev/null; then
        check_pass "Kubernetes API reachable"
    else
        check_fail "Kubernetes API" "Cannot connect to cluster"
        return
    fi
}

check_nodes() {
    print_header "Node Status"

    # Get node status
    NODES_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -c "Ready" || echo "0")
    NODES_TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$NODES_READY" -eq "$NODES_TOTAL" ]] && [[ "$NODES_TOTAL" -gt 0 ]]; then
        check_pass "All nodes ready ($NODES_READY/$NODES_TOTAL)"
    else
        check_fail "Node status" "$NODES_READY/$NODES_TOTAL nodes ready"
    fi

    # Check node resources
    if command -v kubectl &> /dev/null; then
        NODE_INFO=$(kubectl get nodes -o jsonpath='{.items[0].status.allocatable}' 2>/dev/null || echo "{}")
        if [[ -n "$NODE_INFO" ]]; then
            check_pass "Node resources available"
        fi
    fi
}

check_namespaces() {
    print_header "Namespace Status"

    REQUIRED_NS=("infra" "database" "backend" "frontend" "monitoring")

    for ns in "${REQUIRED_NS[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null; then
            check_pass "Namespace: $ns"
        else
            check_warn "Namespace: $ns" "Not found"
        fi
    done
}

check_pods_by_namespace() {
    local ns=$1
    local display_name=$2

    # Get pod counts
    TOTAL=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    RUNNING=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    PENDING=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -c "Pending" || echo "0")
    FAILED=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | grep -cE "Error|CrashLoopBackOff|Failed" || echo "0")

    if [[ "$TOTAL" -eq 0 ]]; then
        check_warn "$display_name pods" "No pods found"
    elif [[ "$FAILED" -gt 0 ]]; then
        check_fail "$display_name pods" "$FAILED pods in error state"
    elif [[ "$PENDING" -gt 0 ]]; then
        check_warn "$display_name pods" "$PENDING pods pending"
    elif [[ "$RUNNING" -eq "$TOTAL" ]]; then
        check_pass "$display_name pods ($RUNNING/$TOTAL running)"
    else
        check_warn "$display_name pods" "$RUNNING/$TOTAL running"
    fi
}

check_all_pods() {
    print_header "Pod Status by Namespace"

    check_pods_by_namespace "kube-system" "System"
    check_pods_by_namespace "infra" "Infrastructure"
    check_pods_by_namespace "database" "Database"
    check_pods_by_namespace "monitoring" "Monitoring"
    check_pods_by_namespace "backend" "Backend"
    check_pods_by_namespace "frontend" "Frontend"
}

check_ingress() {
    print_header "Ingress Controller"

    # Check ingress controller
    INGRESS_POD=$(kubectl get pods -n kube-system -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | grep "Running" | head -1)

    if [[ -n "$INGRESS_POD" ]]; then
        check_pass "NGINX Ingress Controller running"
    else
        check_fail "NGINX Ingress Controller" "Not running"
    fi

    # Check ingress resources
    INGRESS_COUNT=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$INGRESS_COUNT" -gt 0 ]]; then
        check_pass "Ingress resources configured ($INGRESS_COUNT)"
    else
        check_warn "Ingress resources" "None configured"
    fi
}

check_kafka() {
    print_header "Kafka Status"

    # Check Kafka pods
    KAFKA_PODS=$(kubectl get pods -n infra -l app.kubernetes.io/name=kafka --no-headers 2>/dev/null | grep -c "Running" || echo "0")

    if [[ "$KAFKA_PODS" -gt 0 ]]; then
        check_pass "Kafka broker running ($KAFKA_PODS pods)"

        # Check Kafka readiness
        KAFKA_READY=$(kubectl get pods -n infra -l app.kubernetes.io/name=kafka -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [[ "$KAFKA_READY" == *"True"* ]]; then
            check_pass "Kafka broker ready"
        else
            check_warn "Kafka broker" "Not fully ready"
        fi
    else
        check_warn "Kafka" "Not deployed"
    fi

    # Check Kafka UI
    KAFKA_UI=$(kubectl get pods -n infra -l app=kafka-ui --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$KAFKA_UI" -gt 0 ]]; then
        check_pass "Kafka UI running"
    else
        check_warn "Kafka UI" "Not deployed"
    fi
}

check_postgresql() {
    print_header "PostgreSQL Status"

    # Check PostgreSQL pods
    PG_PODS=$(kubectl get pods -n database -l app.kubernetes.io/name=postgresql --no-headers 2>/dev/null | grep -c "Running" || echo "0")

    if [[ "$PG_PODS" -eq 0 ]]; then
        # Try alternative label for custom deployment
        PG_PODS=$(kubectl get pods -n database --no-headers 2>/dev/null | grep -c "postgresql" || echo "0")
    fi

    if [[ "$PG_PODS" -gt 0 ]]; then
        check_pass "PostgreSQL running ($PG_PODS pods)"

        # Test database connection
        if kubectl exec -n database postgresql-0 -- pg_isready -U postgres &>/dev/null 2>&1; then
            check_pass "PostgreSQL accepting connections"
        else
            check_warn "PostgreSQL connection" "Cannot verify connection"
        fi
    else
        check_warn "PostgreSQL" "Not deployed"
    fi

    # Check pgAdmin
    PGADMIN=$(kubectl get pods -n database -l app=pgadmin --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$PGADMIN" -gt 0 ]]; then
        check_pass "pgAdmin running"
    else
        check_warn "pgAdmin" "Not deployed"
    fi
}

check_monitoring() {
    print_header "Monitoring Stack"

    # Check Loki
    LOKI_PODS=$(kubectl get pods -n monitoring -l app=loki --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$LOKI_PODS" -gt 0 ]]; then
        check_pass "Loki running"
    else
        check_warn "Loki" "Not deployed"
    fi

    # Check Promtail
    PROMTAIL_PODS=$(kubectl get pods -n monitoring -l app=promtail --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$PROMTAIL_PODS" -gt 0 ]]; then
        check_pass "Promtail running ($PROMTAIL_PODS pods)"
    else
        check_warn "Promtail" "Not deployed"
    fi

    # Check Grafana
    GRAFANA_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$GRAFANA_PODS" -gt 0 ]]; then
        check_pass "Grafana running"
    else
        check_warn "Grafana" "Not deployed"
    fi

    # Check Prometheus
    PROM_PODS=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$PROM_PODS" -gt 0 ]]; then
        check_pass "Prometheus running ($PROM_PODS pods)"
    else
        check_warn "Prometheus" "Not deployed"
    fi
}

check_services() {
    print_header "Service Endpoints"

    # Check key services have endpoints
    SERVICES=(
        "infra:kafka"
        "database:postgresql"
        "monitoring:prometheus-server"
        "monitoring:loki"
    )

    for svc in "${SERVICES[@]}"; do
        NS="${svc%%:*}"
        NAME="${svc##*:}"

        ENDPOINTS=$(kubectl get endpoints -n "$NS" "$NAME" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")
        if [[ -n "$ENDPOINTS" ]]; then
            check_pass "Service $NAME has endpoints"
        else
            check_warn "Service $NAME" "No endpoints"
        fi
    done
}

check_pvcs() {
    print_header "Persistent Volume Claims"

    # Check PVC status
    BOUND=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep -c "Bound" || echo "0")
    PENDING=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep -c "Pending" || echo "0")
    TOTAL=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$TOTAL" -eq 0 ]]; then
        check_warn "PVCs" "None found"
    elif [[ "$PENDING" -gt 0 ]]; then
        check_warn "PVCs" "$PENDING pending, $BOUND bound"
    else
        check_pass "All PVCs bound ($BOUND/$TOTAL)"
    fi
}

check_resource_usage() {
    print_header "Resource Usage"

    # Check if metrics-server is available
    if kubectl top nodes &>/dev/null 2>&1; then
        NODE_CPU=$(kubectl top nodes --no-headers 2>/dev/null | awk '{print $3}' | tr -d '%')
        NODE_MEM=$(kubectl top nodes --no-headers 2>/dev/null | awk '{print $5}' | tr -d '%')

        if [[ -n "$NODE_CPU" ]]; then
            if [[ "$NODE_CPU" -lt 80 ]]; then
                check_pass "Node CPU usage: ${NODE_CPU}%"
            else
                check_warn "Node CPU usage" "${NODE_CPU}% (high)"
            fi
        fi

        if [[ -n "$NODE_MEM" ]]; then
            if [[ "$NODE_MEM" -lt 85 ]]; then
                check_pass "Node memory usage: ${NODE_MEM}%"
            else
                check_warn "Node memory usage" "${NODE_MEM}% (high)"
            fi
        fi
    else
        check_warn "Resource metrics" "Metrics server not available"
    fi
}

# ============================================================
# Summary Output
# ============================================================

print_summary() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}  Summary${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  Total Checks:   $TOTAL_CHECKS"
        echo -e "  ${GREEN}Passed:${NC}         $PASSED_CHECKS"
        echo -e "  ${YELLOW}Warnings:${NC}       $WARNING_CHECKS"
        echo -e "  ${RED}Failed:${NC}         $FAILED_CHECKS"
        echo ""

        if [[ "$FAILED_CHECKS" -eq 0 ]] && [[ "$WARNING_CHECKS" -eq 0 ]]; then
            echo -e "  ${GREEN}✓ All systems operational${NC}"
        elif [[ "$FAILED_CHECKS" -eq 0 ]]; then
            echo -e "  ${YELLOW}⚠ Systems operational with warnings${NC}"
        else
            echo -e "  ${RED}✗ Some systems require attention${NC}"
        fi
        echo ""
    else
        # JSON output
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"summary\": {"
        echo "    \"total\": $TOTAL_CHECKS,"
        echo "    \"passed\": $PASSED_CHECKS,"
        echo "    \"warnings\": $WARNING_CHECKS,"
        echo "    \"failed\": $FAILED_CHECKS"
        echo "  },"
        echo "  \"checks\": ["
        for i in "${!RESULTS[@]}"; do
            if [[ $i -lt $((${#RESULTS[@]} - 1)) ]]; then
                echo "    ${RESULTS[$i]},"
            else
                echo "    ${RESULTS[$i]}"
            fi
        done
        echo "  ]"
        echo "}"
    fi
}

# ============================================================
# Main Execution
# ============================================================

main() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo ""
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     Mac Mini Infrastructure Health Check                 ║${NC}"
        echo -e "${BLUE}║     $(date '+%Y-%m-%d %H:%M:%S')                               ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    fi

    check_k3d_cluster
    check_kubectl_connection
    check_nodes
    check_namespaces
    check_all_pods
    check_ingress
    check_kafka
    check_postgresql
    check_monitoring
    check_services
    check_pvcs
    check_resource_usage

    print_summary

    # Exit with appropriate code
    if [[ "$FAILED_CHECKS" -gt 0 ]]; then
        exit 1
    elif [[ "$WARNING_CHECKS" -gt 0 ]]; then
        exit 0
    else
        exit 0
    fi
}

# Run main function
main "$@"
