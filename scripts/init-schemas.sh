#!/bin/bash
set -e

# PostgreSQL Schema Initialization for Dev/Prod separation
# This script creates separate schemas for development and production environments

NAMESPACE="infra"
POD_NAME=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=postgresql -o jsonpath='{.items[0].metadata.name}')

echo "🔧 Initializing PostgreSQL schemas..."
echo "📍 Target Pod: $POD_NAME"

# Create schemas and set permissions
kubectl exec -n $NAMESPACE $POD_NAME -- psql -U postgres -d appdb <<-EOSQL
    -- Create schemas
    CREATE SCHEMA IF NOT EXISTS dev_schema;
    CREATE SCHEMA IF NOT EXISTS prod_schema;

    -- Grant permissions to appuser
    GRANT ALL PRIVILEGES ON SCHEMA dev_schema TO appuser;
    GRANT ALL PRIVILEGES ON SCHEMA prod_schema TO appuser;

    -- Set default privileges for future objects
    ALTER DEFAULT PRIVILEGES IN SCHEMA dev_schema GRANT ALL ON TABLES TO appuser;
    ALTER DEFAULT PRIVILEGES IN SCHEMA prod_schema GRANT ALL ON TABLES TO appuser;
    ALTER DEFAULT PRIVILEGES IN SCHEMA dev_schema GRANT ALL ON SEQUENCES TO appuser;
    ALTER DEFAULT PRIVILEGES IN SCHEMA prod_schema GRANT ALL ON SEQUENCES TO appuser;

    -- Set search path for appuser (optional: dev first, then prod)
    ALTER ROLE appuser SET search_path = dev_schema, prod_schema, public;

    -- Show created schemas
    \dn
EOSQL

echo "✅ Schemas created successfully!"
echo ""
echo "📊 Connection strings:"
echo "   Dev:  postgresql://appuser@postgresql.infra.svc.cluster.local:5432/appdb?currentSchema=dev_schema"
echo "   Prod: postgresql://appuser@postgresql.infra.svc.cluster.local:5432/appdb?currentSchema=prod_schema"
