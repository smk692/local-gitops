#!/bin/bash

# ============================================================
# Common Library - Shared functions for infrastructure scripts
# ============================================================

# Prevent multiple sourcing
[[ -n "$_COMMON_SH_LOADED" ]] && return
_COMMON_SH_LOADED=1

# ============================================================
# Color Definitions
# ============================================================

export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[1;37m'
export NC='\033[0m' # No Color
export BOLD='\033[1m'

# ============================================================
# Logging Functions
# ============================================================

# Log file setup
setup_logging() {
    local log_dir="${1:-$PROJECT_ROOT/logs}"
    mkdir -p "$log_dir"
    export LOG_FILE="$log_dir/deploy-$(date +%Y%m%d-%H%M%S).log"
    echo "Logging to: $LOG_FILE"
}

# Log with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Console output
    case "$level" in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        DEBUG)
            [[ "$DEBUG" == "true" ]] && echo -e "${PURPLE}[DEBUG]${NC} $message"
            ;;
        *)
            echo "$message"
            ;;
    esac

    # File output (if LOG_FILE is set)
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

log_info() { log INFO "$@"; }
log_success() { log SUCCESS "$@"; }
log_warn() { log WARN "$@"; }
log_error() { log ERROR "$@"; }
log_debug() { log DEBUG "$@"; }

# ============================================================
# UI Functions
# ============================================================

print_header() {
    local title="$1"
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $title${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_banner() {
    local title="$1"
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}$title${NC}"
    echo -e "${CYAN}║${NC}  $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step_num="$1"
    local step_name="$2"
    echo ""
    echo -e "${GREEN}▶ Step $step_num: $step_name${NC}"
    echo -e "${GREEN}─────────────────────────────────────────${NC}"
}

print_substep() {
    local message="$1"
    echo -e "  ${CYAN}→${NC} $message"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_fail() {
    echo -e "  ${RED}✗${NC} $1"
}

print_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

# Progress spinner
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "      \b\b\b\b\b\b"
}

# ============================================================
# Error Handling
# ============================================================

# Error handler
handle_error() {
    local exit_code=$?
    local line_num=$1
    log_error "Error occurred at line $line_num (exit code: $exit_code)"

    if [[ -n "$CHECKPOINT_FILE" ]] && [[ -f "$CHECKPOINT_FILE" ]]; then
        log_info "Checkpoint saved. You can resume from the last successful step."
    fi

    exit $exit_code
}

# Setup error trap
setup_error_handling() {
    trap 'handle_error $LINENO' ERR
}

# ============================================================
# Checkpoint Management
# ============================================================

# Initialize checkpoint file
init_checkpoint() {
    export CHECKPOINT_FILE="${1:-$PROJECT_ROOT/.deploy-checkpoint}"
    if [[ -f "$CHECKPOINT_FILE" ]]; then
        log_info "Found existing checkpoint file"
        source "$CHECKPOINT_FILE"
    else
        echo "# Deployment Checkpoint" > "$CHECKPOINT_FILE"
        echo "LAST_SUCCESSFUL_PHASE=0" >> "$CHECKPOINT_FILE"
    fi
}

# Save checkpoint
save_checkpoint() {
    local phase="$1"
    if [[ -n "$CHECKPOINT_FILE" ]]; then
        echo "LAST_SUCCESSFUL_PHASE=$phase" > "$CHECKPOINT_FILE"
        echo "CHECKPOINT_TIME=$(date +%s)" >> "$CHECKPOINT_FILE"
        log_debug "Checkpoint saved: phase $phase"
    fi
}

# Check if phase should be skipped
should_skip_phase() {
    local phase="$1"
    if [[ -n "$LAST_SUCCESSFUL_PHASE" ]] && [[ "$phase" -le "$LAST_SUCCESSFUL_PHASE" ]]; then
        return 0  # Should skip
    fi
    return 1  # Should not skip
}

# Clear checkpoint
clear_checkpoint() {
    if [[ -n "$CHECKPOINT_FILE" ]] && [[ -f "$CHECKPOINT_FILE" ]]; then
        rm -f "$CHECKPOINT_FILE"
        log_info "Checkpoint cleared"
    fi
}

# ============================================================
# Utility Functions
# ============================================================

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Wait for pod to be ready
wait_for_pod() {
    local namespace="$1"
    local label="$2"
    local timeout="${3:-300}"

    log_info "Waiting for pod with label '$label' in namespace '$namespace'..."
    kubectl wait --namespace "$namespace" \
        --for=condition=ready pod \
        --selector="$label" \
        --timeout="${timeout}s"
}

# Wait for deployment rollout
wait_for_deployment() {
    local namespace="$1"
    local deployment="$2"
    local timeout="${3:-300}"

    log_info "Waiting for deployment '$deployment' in namespace '$namespace'..."
    kubectl rollout status deployment/"$deployment" \
        --namespace "$namespace" \
        --timeout="${timeout}s"
}

# Check if namespace exists
namespace_exists() {
    kubectl get namespace "$1" &> /dev/null
}

# Check if resource exists
resource_exists() {
    local type="$1"
    local name="$2"
    local namespace="${3:-default}"

    kubectl get "$type" "$name" -n "$namespace" &> /dev/null
}

# Get secret value
get_secret_value() {
    local secret_name="$1"
    local key="$2"
    local namespace="${3:-default}"

    kubectl get secret "$secret_name" -n "$namespace" \
        -o jsonpath="{.data.$key}" 2>/dev/null | base64 -d
}

# ============================================================
# Confirmation Functions
# ============================================================

# Ask for confirmation
confirm() {
    local message="${1:-Are you sure?}"
    read -p "$message (y/n) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# Ask for confirmation with default yes
confirm_default_yes() {
    local message="${1:-Are you sure?}"
    read -p "$message (Y/n) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Nn]$ ]]
}

# ============================================================
# Environment Functions
# ============================================================

# Load environment from file
load_env() {
    local env_file="${1:-.env}"
    if [[ -f "$env_file" ]]; then
        log_debug "Loading environment from $env_file"
        set -a
        source "$env_file"
        set +a
    fi
}

# Check required environment variables
check_required_env() {
    local missing=()
    for var in "$@"; do
        if [[ -z "${!var}" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing[*]}"
        return 1
    fi
    return 0
}

# ============================================================
# Resource Profile Functions
# ============================================================

# Get resource profile based on system memory
get_resource_profile() {
    local total_mem_gb

    if [[ "$OSTYPE" == "darwin"* ]]; then
        total_mem_gb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
    else
        total_mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    fi

    if [[ $total_mem_gb -ge 32 ]]; then
        echo "32gb"
    elif [[ $total_mem_gb -ge 16 ]]; then
        echo "16gb"
    else
        echo "8gb"
    fi
}

# ============================================================
# Export all functions
# ============================================================

export -f log log_info log_success log_warn log_error log_debug
export -f print_header print_banner print_step print_substep
export -f print_success print_fail print_warn
export -f command_exists wait_for_pod wait_for_deployment
export -f namespace_exists resource_exists get_secret_value
export -f confirm confirm_default_yes
export -f load_env check_required_env get_resource_profile
export -f init_checkpoint save_checkpoint should_skip_phase clear_checkpoint
