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


# Clear data
echo "Clearing data"
rm -rf ./postgres-master-data/* 2>/dev/null || true
rm -rf ./postgres-replica-data/* 2>/dev/null || true
docker compose down -v 2>/dev/null || true


# Start master
echo "Starting postgres-master node..."
docker compose up -d postgres-master

# Wait for master to be ready
echo "Waiting for master to start..."
for i in {1..30}; do
    if docker exec postgres-master pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
        echo "Master is ready!"
        break
    fi
    sleep 2
    if [ $i -eq 30 ]; then
        echo "ERROR: Master failed to start within 60 seconds"
        exit 1
    fi
done


# Create DBs, role and publications
echo "Creating DBs, role and publications..."

# Function of creation DB, if not exists
create_db_if_not_exists() {
  local db_name=$1
  local db_exists=$(docker exec -i postgres-master psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'")
  if [ "$db_exists" != "1" ]; then
    docker exec -i postgres-master psql -U postgres -c "CREATE DATABASE $db_name;"
  fi
}

create_db_if_not_exists "user_service_db"
create_db_if_not_exists "order_service_db"
create_db_if_not_exists "logistics_service_db"

docker exec -i postgres-master psql -U postgres -d postgres <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='dbzuser') THEN
    CREATE ROLE dbzuser WITH LOGIN REPLICATION PASSWORD 'dbzpass';
    ALTER ROLE dbzuser WITH SUPERUSER;
  END IF;
END$$;
SQL


# Create publications
echo "Creating publications (if missing)..."

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
docker exec -it postgres-master sh /etc/postgresql/init-script/init.sh

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


echo "Connection strings:"
echo "  Master:      postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_MASTER_PORT/$POSTGRES_DB"
echo "  Replica:     postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_REPLICA_PORT/$POSTGRES_DB"
echo ""
echo "=== Setup completed successfully! ==="
