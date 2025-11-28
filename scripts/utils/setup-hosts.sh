#!/bin/bash

# ============================================================
# /etc/hosts Configuration Script
# Manages host entries for local development
# ============================================================

set -e

# Configuration
HOSTS_FILE="/etc/hosts"
MARKER_START="# === Mac Mini Infrastructure Start ==="
MARKER_END="# === Mac Mini Infrastructure End ==="

# Host entries
HOST_IP="127.0.0.1"
HOSTS=(
    "kafka-ui.son.duckdns.org"
    "pgadmin.son.duckdns.org"
    "grafana.son.duckdns.org"
    "prometheus.son.duckdns.org"
    "app.son.duckdns.org"
    "api.son.duckdns.org"
    "argocd.son.duckdns.org"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Functions
# ============================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    cat <<EOF
Usage: $0 [COMMAND]

Manage /etc/hosts entries for Mac Mini infrastructure.

Commands:
  add       Add host entries (requires sudo)
  remove    Remove host entries (requires sudo)
  check     Check if entries exist
  show      Show entries that would be added
  backup    Backup current /etc/hosts

Options:
  -h, --help    Show this help message

Examples:
  sudo $0 add       # Add entries to /etc/hosts
  sudo $0 remove    # Remove entries from /etc/hosts
  $0 check          # Check current status
  $0 show           # Show entries to be added

EOF
}

check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This command requires sudo privileges"
        echo "Run: sudo $0 $1"
        exit 1
    fi
}

backup_hosts() {
    local backup_file="/etc/hosts.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$HOSTS_FILE" "$backup_file"
    log_success "Backup created: $backup_file"
}

show_entries() {
    echo ""
    log_info "Host entries for Mac Mini infrastructure:"
    echo ""
    echo "$MARKER_START"
    for host in "${HOSTS[@]}"; do
        echo "$HOST_IP    $host"
    done
    echo "$MARKER_END"
    echo ""
}

check_entries() {
    local found=0
    local missing=0

    echo ""
    log_info "Checking /etc/hosts entries:"
    echo ""

    for host in "${HOSTS[@]}"; do
        if grep -q "$host" "$HOSTS_FILE" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $host"
            ((found++))
        else
            echo -e "  ${RED}✗${NC} $host"
            ((missing++))
        fi
    done

    echo ""
    if [[ $missing -eq 0 ]]; then
        log_success "All entries present ($found/${#HOSTS[@]})"
        return 0
    else
        log_warn "Missing entries: $missing/${#HOSTS[@]}"
        return 1
    fi
}

add_entries() {
    check_sudo "add"

    # Check if entries already exist
    if grep -q "$MARKER_START" "$HOSTS_FILE" 2>/dev/null; then
        log_warn "Entries already exist. Removing old entries first..."
        remove_entries_internal
    fi

    # Backup
    backup_hosts

    # Add entries
    {
        echo ""
        echo "$MARKER_START"
        for host in "${HOSTS[@]}"; do
            echo "$HOST_IP    $host"
        done
        echo "$MARKER_END"
    } >> "$HOSTS_FILE"

    log_success "Host entries added to $HOSTS_FILE"
    echo ""
    log_info "You can now access services at:"
    for host in "${HOSTS[@]}"; do
        echo "  http://${host}:8080"
    done
}

remove_entries_internal() {
    # Remove entries between markers (used internally)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"
    else
        sed -i "/$MARKER_START/,/$MARKER_END/d" "$HOSTS_FILE"
    fi
}

remove_entries() {
    check_sudo "remove"

    if ! grep -q "$MARKER_START" "$HOSTS_FILE" 2>/dev/null; then
        log_info "No Mac Mini infrastructure entries found"
        return 0
    fi

    # Backup
    backup_hosts

    # Remove entries
    remove_entries_internal

    log_success "Host entries removed from $HOSTS_FILE"
}

# ============================================================
# Main
# ============================================================

main() {
    local command="${1:-check}"

    case "$command" in
        add)
            add_entries
            ;;
        remove)
            remove_entries
            ;;
        check)
            check_entries
            ;;
        show)
            show_entries
            ;;
        backup)
            check_sudo "backup"
            backup_hosts
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
