#!/bin/bash
set -e

echo "=== Starting DWH setup ==="


# Create .env if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env from .env.example..."
    if [ -f .env.example ]; then
        cp .env.example .env
        echo ".env created successfully"
    else
        echo "ERROR: .env.example not found!"
        echo "Please create .env file manually"
        exit 1
    fi
fi

# Load environment variables
source .env 2>/dev/null || echo "WARNING: .env not found, using defaults"


echo "=== Generating Data Vault 2.0 DDL ==="
rm -f ./dwh/ddl*.sql 2>/dev/null || true

docker run --rm -v "$(pwd):/app" -w /app python:3.12-slim bash -c "pip install pyyaml --root-user-action=ignore && python dwh/generate_ddl.py"

if [ ! -f "./dwh/ddl/001_dwh_detailed_ddl_generated.sql" ]; then
    echo "ERROR: DDL generation failed"
    exit 1
fi
echo "DDL generated successfully in dwh/ddl"

# Clear data
echo "Clearing data"
rm -rf ./postgres-master-data/* 2>/dev/null || true
rm -rf ./postgres-replica-data/* 2>/dev/null || true
rm -rf ./postgres-dwh-data/* 2>/dev/null || true

docker compose down -v 2>/dev/null || true


# Start master
echo "Starting postgres-master node..."
docker compose up -d postgres-master

echo "Waiting for master to complete initialization and become healthy..."
for i in {1..40}; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' postgres-master 2>/dev/null || echo "starting")
    
    if [ "$STATUS" = "healthy" ]; then
        echo "Master is fully initialized and healthy!"
        break
    fi
    sleep 2
    if [ $i -eq 40 ]; then
        echo "ERROR: Master failed to become healthy within 80 seconds"
        docker logs postgres-master --tail 50
        exit 1
    fi
done

until docker exec postgres-master pg_isready -U "$POSTGRES_USER" -h 127.0.0.1 > /dev/null 2>&1; do
    echo "Waiting for TCP socket to open..."
    sleep 2
done
echo "PostgreSQL is accepting queries."

# Create DBs, role and publications
echo "Creating databases if they don't exist..."
create_db_if_not_exists() {
    local db_name=$1
    local exists=$(docker exec postgres-master psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'")
    if [ "$exists" != "1" ]; then
        docker exec postgres-master psql -U postgres -c "CREATE DATABASE $db_name" 2>/dev/null || true
        echo "Database $db_name created"
    else
        echo "Database $db_name already exists"
    fi
}

create_db_if_not_exists "user_service_db"
create_db_if_not_exists "order_service_db"
create_db_if_not_exists "logistics_service_db"


# Create replication user
docker exec -i postgres-master psql -U postgres -d postgres <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='dbzuser') THEN
    CREATE ROLE dbzuser WITH LOGIN REPLICATION PASSWORD 'dbzpass';
    ALTER ROLE dbzuser WITH SUPERUSER;
  END IF;
END$$;
SQL


# Create tables in each service database 
echo "Creating tables in service databases..."

apply_sql_file() {
    local db_name=$1
    local sql_file=$2
    if [ -f "$sql_file" ]; then
        echo "Applying $sql_file to $db_name"
        docker exec -i postgres-master psql -U postgres -d "$db_name" < "$sql_file"
    else
        echo "WARNING: SQL file $sql_file not found, skipping $db_name"
    fi
}

echo "Creating tables in service databases..."
apply_sql_file "user_service_db" "./migrations/001_user_service_db.sql"
apply_sql_file "order_service_db" "./migrations/002_order_service_db.sql"
apply_sql_file "logistics_service_db" "./migrations/003_logistics_service_db.sql"


# Create publications
echo "Creating publications..."

create_publication_if_not_exists() {
    local db_name=$1
    local pub_name=$2
    local tables=$3

    local pub_exists=$(docker exec -i postgres-master psql -U postgres -d "$db_name" -tAc "SELECT 1 FROM pg_publication WHERE pubname='$pub_name'")
    if [ "$pub_exists" != "1" ]; then
        docker exec -i postgres-master psql -U postgres -d "$db_name" -c "CREATE PUBLICATION $pub_name FOR TABLE $tables;"
        echo "Publication $pub_name created in $db_name."
    else
        echo "Publication $pub_name already exists in $db_name."
    fi
}

create_publication_if_not_exists "user_service_db" "dbz_pub_user_service" "public.users, public.user_addresses, public.user_status_history"
create_publication_if_not_exists "order_service_db" "dbz_pub_order_service" "public.orders, public.products, public.order_items, public.order_status_history"
create_publication_if_not_exists "logistics_service_db" "dbz_pub_logistics_service" "public.warehouses, public.pickup_points, public.shipments, public.shipment_movements, public.shipment_status_history"

echo "DBs, role and publications ensured."


# Prepare replica config
echo "Prepare replica config..."

rm -rf ./postgres-replica-data/* 2>/dev/null || true

docker exec -i \
  -e PGPASSWORD="dbzpass" \
  postgres-master pg_basebackup -h 127.0.0.1 -p 5432 -U dbzuser -D /tmp/replica_data -Fp -Xs -c fast -R

docker exec -i postgres-master sed -i 's/host=127.0.0.1/host=postgres-master/g' /tmp/replica_data/postgresql.auto.conf

docker cp postgres-master:/tmp/replica_data/. ./postgres-replica-data/

docker exec -i postgres-master rm -rf /tmp/replica_data

echo "Replica data prepared successfully!"


# Restart master
echo "Restart master node"
docker compose restart postgres-master
sleep 5


# Start replica
echo "Starting replica node..."
docker compose up -d postgres-replica

# Wait for replica to be ready
echo "Waiting for replica to start..."
for i in {1..30}; do
    if docker exec postgres-replica pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
        echo "Replica is ready!"
        break
    fi
    sleep 2
    if [ $i -eq 30 ]; then
        echo "ERROR: Replica failed to start within 60 seconds"
        exit 1
    fi
done


# Start Kafka
echo "Starting kafka..."
docker compose up -d kafka

echo "Waiting for Kafka broker to accept API..."
# Wait until kafka-broker-api-versions works
for i in {1..60}; do
    if docker exec kafka bash -c "kafka-broker-api-versions --bootstrap-server localhost:9092 >/dev/null 2>&1"; then
        echo "Kafka broker is reachable"
        break
    fi
    sleep 2
    if [ "$i" -eq 60 ]; then
        echo "ERROR: Kafka broker did not become ready"
        docker logs kafka --tail 200
        exit 1
    fi
done

echo "Waiting for Kafka topics API to be ready..."
for i in {1..30}; do
    if docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
        echo "Kafka topics API is ready!"
        break
    fi
    sleep 2
    if [ "$i" -eq 30 ]; then
        echo "ERROR: Kafka topics API did not become ready"
        exit 1
    fi
done


# Create Debezium topics
echo "Creating Debezium internal topics..."
docker exec kafka bash -lc "\
  kafka-topics --bootstrap-server localhost:9092 --create --replication-factor 1 --partitions 1 --topic debezium_configs --config cleanup.policy=compact || true && \
  kafka-topics --bootstrap-server localhost:9092 --create --replication-factor 1 --partitions 1 --topic debezium_offsets --config cleanup.policy=compact || true && \
  kafka-topics --bootstrap-server localhost:9092 --create --replication-factor 1 --partitions 1 --topic debezium_statuses --config cleanup.policy=compact || true \
"
echo "Debezium topics ensured."


# Start Debezium
echo "Starting debezium..."
docker compose up -d debezium

echo "Waiting for Debezium Connect REST to be available..."
for i in {1..60}; do
  if curl -fsS "http://localhost:${DEBEZIUM_PORT:-8083}/" >/dev/null 2>&1; then
    echo "Debezium Connect is up"
    break
  fi
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "ERROR: Debezium Connect did not start"
    docker logs debezium --tail 200
    exit 1
  fi
done


# Register connectors
if [ -f ./debezium/register-connectors.sh ]; then
  echo "Registering connectors via debezium/register-connectors.sh ..."
  chmod +x ./debezium/register-connectors.sh
  ./debezium/register-connectors.sh
else
  echo "Skip registration: ./debezium/register-connectors.sh not found. You can register connectors manually or add the script."
fi


# Start DMP service
echo "Starting DMP Service..."
docker compose up -d dmp-service
echo "DMP Service is running"


echo "Connection strings:"
echo "  Master:      postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_MASTER_PORT/$POSTGRES_DB"
echo "  Replica:     postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_REPLICA_PORT/$POSTGRES_DB"
echo ""
echo "=== Setup completed successfully! ==="
