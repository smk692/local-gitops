#!/bin/bash

# ============================================================
# Phase 3: Database Setup
# Deploys PostgreSQL and initializes schemas
# ============================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Database directory (separate from infra)
DATABASE_ROOT="/Users/sonmingi/Desktop/database"

# Source libraries
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/validation.sh"

# ============================================================
# Phase 3 Main Function
# ============================================================

phase_03_database() {
    print_header "Phase 3: Database Setup"

    # Validate prerequisites
    print_step "3.0" "Prerequisites Check"
    validate_kubectl || return 1

    # Step 3.1: Create database namespace
    print_step "3.1" "Database Namespace"
    create_database_namespace || return 1

    # Step 3.2: Deploy PostgreSQL
    print_step "3.2" "PostgreSQL Deployment"
    deploy_postgresql || return 1

    # Step 3.3: Initialize schemas
    print_step "3.3" "Schema Initialization"
    init_schemas || return 1

    # Step 3.4: Deploy pgAdmin
    print_step "3.4" "pgAdmin Deployment"
    deploy_pgadmin || return 1

    # Step 3.5: Verify database
    print_step "3.5" "Database Verification"
    verify_database || return 1

    log_success "Phase 3 completed successfully"
    return 0
}

# ============================================================
# Database Functions
# ============================================================

create_database_namespace() {
    if ! namespace_exists "database"; then
        log_info "Creating database namespace..."
        kubectl create namespace database
    fi
    print_success "Database namespace ready"
    return 0
}

deploy_postgresql() {
    local pg_manifest="$DATABASE_ROOT/k3s/postgres.yaml"
    local init_job="$DATABASE_ROOT/k3s/init-job.yaml"

    log_info "Deploying PostgreSQL..."

    # Check if manifest exists
    if [[ -f "$pg_manifest" ]]; then
        kubectl apply -f "$pg_manifest"
        print_success "PostgreSQL manifests applied"
    else
        log_warn "PostgreSQL manifest not found at $pg_manifest"
        log_info "Attempting to deploy using project infra..."

        # Fallback to infra directory
        local infra_pg="$PROJECT_ROOT/k8s/postgres/"
        if [[ -d "$infra_pg" ]]; then
            kubectl apply -f "$infra_pg" -n database
        else
            log_error "No PostgreSQL manifests found"
            return 1
        fi
    fi

    # Wait for PostgreSQL to be ready
    log_info "Waiting for PostgreSQL to be ready..."
    kubectl wait --namespace database \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/name=postgresql \
        --timeout=300s 2>/dev/null || \
    kubectl wait --namespace database \
        --for=condition=ready pod \
        -l app=postgresql \
        --timeout=300s 2>/dev/null || \
    {
        # Try with StatefulSet name directly
        sleep 30
        kubectl wait --namespace database \
            --for=condition=ready pod \
            postgresql-0 \
            --timeout=300s 2>/dev/null || log_warn "PostgreSQL may not be fully ready"
    }

    print_success "PostgreSQL deployed"
    return 0
}

init_schemas() {
    local init_job="$DATABASE_ROOT/k3s/init-job.yaml"

    log_info "Initializing database schemas..."

    # Check if init job exists
    if [[ -f "$init_job" ]]; then
        # Delete any existing job first
        kubectl delete job postgres-init-schemas -n database 2>/dev/null || true

        # Apply the init job
        kubectl apply -f "$init_job"

        # Wait for job to complete
        log_info "Waiting for schema initialization to complete..."
        kubectl wait --namespace database \
            --for=condition=complete job/postgres-init-schemas \
            --timeout=120s 2>/dev/null || {
            log_warn "Schema init job may not have completed"
            # Check job status
            kubectl get jobs -n database
        }

        print_success "Schemas initialized via Job"
    else
        log_info "Init job not found, running inline schema initialization..."
        init_schemas_inline
    fi

    return 0
}

init_schemas_inline() {
    # Get PostgreSQL pod
    local pg_pod=$(kubectl get pods -n database -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$pg_pod" ]]; then
        pg_pod=$(kubectl get pods -n database -o name 2>/dev/null | grep postgresql | head -1 | sed 's/pod\///')
    fi

    if [[ -z "$pg_pod" ]]; then
        log_warn "PostgreSQL pod not found, skipping schema initialization"
        return 0
    fi

    log_info "Initializing schemas on pod: $pg_pod"

    # Create schemas
    kubectl exec -n database "$pg_pod" -- psql -U postgres -d appdb -c "
        -- Create appuser if not exists
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'appuser') THEN
                CREATE ROLE appuser WITH LOGIN PASSWORD 'appuser123';
            END IF;
        END
        \$\$;

        -- Create schemas
        CREATE SCHEMA IF NOT EXISTS dev_schema;
        CREATE SCHEMA IF NOT EXISTS prod_schema;

        -- Grant permissions
        GRANT ALL ON SCHEMA dev_schema TO appuser;
        GRANT ALL ON SCHEMA prod_schema TO appuser;

        -- Set default privileges
        ALTER DEFAULT PRIVILEGES IN SCHEMA dev_schema GRANT ALL ON TABLES TO appuser;
        ALTER DEFAULT PRIVILEGES IN SCHEMA dev_schema GRANT ALL ON SEQUENCES TO appuser;
        ALTER DEFAULT PRIVILEGES IN SCHEMA dev_schema GRANT ALL ON FUNCTIONS TO appuser;

        ALTER DEFAULT PRIVILEGES IN SCHEMA prod_schema GRANT ALL ON TABLES TO appuser;
        ALTER DEFAULT PRIVILEGES IN SCHEMA prod_schema GRANT ALL ON SEQUENCES TO appuser;
        ALTER DEFAULT PRIVILEGES IN SCHEMA prod_schema GRANT ALL ON FUNCTIONS TO appuser;
    " 2>/dev/null || log_warn "Schema initialization may have already been done"

    print_success "Schemas initialized inline"
    return 0
}

deploy_pgadmin() {
    local pgadmin_manifest="$DATABASE_ROOT/k3s/pgadmin.yaml"

    log_info "Deploying pgAdmin..."

    if [[ -f "$pgadmin_manifest" ]]; then
        kubectl apply -f "$pgadmin_manifest"
    else
        log_info "pgAdmin manifest not found, deploying inline..."
        deploy_pgadmin_inline
    fi

    # Wait for pgAdmin to be ready
    log_info "Waiting for pgAdmin to be ready..."
    kubectl wait --namespace database \
        --for=condition=ready pod \
        --selector=app=pgadmin \
        --timeout=180s 2>/dev/null || log_warn "pgAdmin may not be fully ready"

    print_success "pgAdmin deployed"
    return 0
}

deploy_pgadmin_inline() {
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: pgadmin-secret
  namespace: database
type: Opaque
stringData:
  email: admin@local.dev
  password: admin123
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pgadmin
  namespace: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pgadmin
  template:
    metadata:
      labels:
        app: pgadmin
    spec:
      containers:
      - name: pgadmin
        image: dpage/pgadmin4:latest
        ports:
        - containerPort: 80
        env:
        - name: PGADMIN_DEFAULT_EMAIL
          valueFrom:
            secretKeyRef:
              name: pgadmin-secret
              key: email
        - name: PGADMIN_DEFAULT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pgadmin-secret
              key: password
        - name: PGADMIN_CONFIG_SERVER_MODE
          value: "False"
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: pgadmin
  namespace: database
spec:
  selector:
    app: pgadmin
  ports:
  - port: 80
    targetPort: 80
EOF
}

# ============================================================
# Verification Functions
# ============================================================

verify_database() {
    log_info "Verifying database setup..."

    local errors=0

    # Check PostgreSQL
    local pg_running=$(kubectl get pods -n database --no-headers 2>/dev/null | grep -c "postgresql.*Running" || echo "0")
    if [[ "$pg_running" -gt 0 ]]; then
        print_success "PostgreSQL is running"

        # Test connection
        test_postgres_connection
    else
        log_error "PostgreSQL is not running"
        ((errors++))
    fi

    # Check pgAdmin
    local pgadmin_running=$(kubectl get pods -n database -l app=pgadmin --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$pgadmin_running" -gt 0 ]]; then
        print_success "pgAdmin is running"
    else
        log_warn "pgAdmin is not running"
    fi

    # Display pods
    echo ""
    log_info "Database pods:"
    kubectl get pods -n database

    # Display services
    echo ""
    log_info "Database services:"
    kubectl get svc -n database

    if [[ $errors -gt 0 ]]; then
        return 1
    fi

    return 0
}

test_postgres_connection() {
    local pg_pod=$(kubectl get pods -n database -o name 2>/dev/null | grep postgresql | head -1 | sed 's/pod\///')

    if [[ -n "$pg_pod" ]]; then
        if kubectl exec -n database "$pg_pod" -- pg_isready -U postgres &>/dev/null; then
            print_success "PostgreSQL is accepting connections"
        else
            log_warn "PostgreSQL connection test failed"
        fi

        # List schemas
        log_info "Available schemas:"
        kubectl exec -n database "$pg_pod" -- psql -U postgres -d appdb -c "\dn" 2>/dev/null || true
    fi
}

# ============================================================
# Run Phase
# ============================================================

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    phase_03_database
fi
