#!/bin/bash
set -e

echo "=== Starting DWH + Airflow + BI setup ==="


# ──────────────────────────────────────────────────────
# 1. Create .env
# ──────────────────────────────────────────────────────
if [ ! -f .env ]; then
    echo "Creating .env from .env.example..."
    if [ -f .env.example ]; then
        cp .env.example .env
        echo "✅ .env created successfully"
    else
        echo "❌ ERROR: .env.example not found!"
        echo "Please create .env file manually"
        exit 1
    fi
fi
# Load environment variables
source .env 2>/dev/null || echo "WARNING: .env not found, using defaults"


# ──────────────────────────────────────────────────────
# 2. Generate Data Vault 2.0 DDL
# ──────────────────────────────────────────────────────
echo "=== Generating Data Vault 2.0 DDL ==="
rm -f ./dwh/ddl*.sql 2>/dev/null || true

docker run --rm -v "$(pwd):/app" -w /app python:3.12-slim bash -c "pip install pyyaml --root-user-action=ignore && python dwh/generate_ddl.py"

if [ ! -f "./dwh/ddl/001_starrocks_dwh_detailed.sql" ]; then
    echo "❌ ERROR: DDL generation failed"
    exit 1
fi
echo "✅ DDL generated successfully in dwh/ddl"


# ──────────────────────────────────────────────────────
# 3. Clear data volumes
# ──────────────────────────────────────────────────────
echo "=== Clearing data ==="
docker compose down -v 2>/dev/null || true
rm -rf ./postgres-master-data/* 2>/dev/null || true
rm -rf ./postgres-replica-data/* 2>/dev/null || true
rm -rf ./starrocks-data/* 2>/dev/null || true


# ──────────────────────────────────────────────────────
# 4. Build custom images (Airflow with pymysql)
# ──────────────────────────────────────────────────────
echo "=== Building custom Docker images ==="
docker compose build airflow-init airflow-scheduler airflow-webserver


# ──────────────────────────────────────────────────────
# 5. Start Postgres Master
# ──────────────────────────────────────────────────────
echo "=== Starting postgres-master ==="
docker compose up -d postgres-master

echo "Waiting for master to become healthy..."
for i in {1..40}; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' postgres-master 2>/dev/null || echo "starting")
    if [ "$STATUS" = "healthy" ]; then
        echo "✅ Master is healthy!"
        break
    fi
    sleep 2
    if [ $i -eq 40 ]; then
        echo "❌ ERROR: Master failed to become healthy"
        docker logs postgres-master --tail 50
        exit 1
    fi
done

until docker exec postgres-master pg_isready -U "$POSTGRES_USER" -h 127.0.0.1 > /dev/null 2>&1; do
    sleep 2
done
echo "✅ PostgreSQL is accepting queries."


# ──────────────────────────────────────────────────────
# 6. Create databases
# ──────────────────────────────────────────────────────
echo "=== Creating databases ==="
create_db_if_not_exists() {
    local db_name=$1
    local exists=$(docker exec postgres-master psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$db_name'")
    if [ "$exists" != "1" ]; then
        docker exec postgres-master psql -U postgres -c "CREATE DATABASE $db_name" 2>/dev/null || true
        echo "✅ Database $db_name created"
    else
        echo "✅ Database $db_name already exists"
    fi
}

create_db_if_not_exists "user_service_db"
create_db_if_not_exists "order_service_db"
create_db_if_not_exists "logistics_service_db"
create_db_if_not_exists "airflow_db"


# ──────────────────────────────────────────────────────
# 7. Create replication / Debezium user
# ──────────────────────────────────────────────────────
docker exec -i postgres-master psql -U postgres -d postgres <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='dbzuser') THEN
    CREATE ROLE dbzuser WITH LOGIN REPLICATION PASSWORD 'dbzpass';
    ALTER ROLE dbzuser WITH SUPERUSER;
  END IF;
END$$;
SQL


# ──────────────────────────────────────────────────────
# 8. Apply migrations
# ──────────────────────────────────────────────────────
echo "=== Applying migrations ==="
apply_sql_file() {
    local db_name=$1
    local sql_file=$2
    if [ -f "$sql_file" ]; then
        echo "✅ Applying $sql_file to $db_name"
        docker exec -i postgres-master psql -U postgres -d "$db_name" < "$sql_file"
    else
        echo "⚠️ WARNING: SQL file $sql_file not found, skipping $db_name"
    fi
}

echo "Creating tables in service databases..."
apply_sql_file "user_service_db"        "./migrations/001_user_service_db.sql"
apply_sql_file "order_service_db"       "./migrations/002_order_service_db.sql"
apply_sql_file "logistics_service_db"   "./migrations/003_logistics_service_db.sql"


# ──────────────────────────────────────────────────────
# 9. Create Debezium publications
# ──────────────────────────────────────────────────────
echo "=== Creating publications ==="
create_publication_if_not_exists() {
    local db_name=$1
    local pub_name=$2
    local tables=$3

    local pub_exists=$(docker exec -i postgres-master psql -U postgres -d "$db_name" -tAc "SELECT 1 FROM pg_publication WHERE pubname='$pub_name'")
    if [ "$pub_exists" != "1" ]; then
        docker exec -i postgres-master psql -U postgres -d "$db_name" -c "CREATE PUBLICATION $pub_name FOR TABLE $tables;"
        echo "✅ Publication $pub_name created in $db_name."
    fi
}

create_publication_if_not_exists "user_service_db" "dbz_pub_user_service" "public.users, public.user_addresses, public.user_status_history"
create_publication_if_not_exists "order_service_db" "dbz_pub_order_service" "public.orders, public.products, public.order_items, public.order_status_history"
create_publication_if_not_exists "logistics_service_db" "dbz_pub_logistics_service" "public.warehouses, public.pickup_points, public.shipments, public.shipment_movements, public.shipment_status_history"

echo "✅ DBs, role and publications ensured."


# ──────────────────────────────────────────────────────
# 10. Prepare & Start Postgres Replica
# ──────────────────────────────────────────────────────
echo "=== Setting up postgres-replica ==="
rm -rf ./postgres-replica-data/* 2>/dev/null || true

docker exec -i -e PGPASSWORD="dbzpass" postgres-master \
  pg_basebackup -h 127.0.0.1 -p 5432 -U dbzuser -D /tmp/replica_data -Fp -Xs -c fast -R

docker exec -i postgres-master \
  sed -i 's/host=127.0.0.1/host=postgres-master/g' /tmp/replica_data/postgresql.auto.conf

docker cp postgres-master:/tmp/replica_data/. ./postgres-replica-data/
docker exec -i postgres-master rm -rf /tmp/replica_data
docker compose restart postgres-master
sleep 5

docker compose up -d postgres-replica

for i in {1..30}; do
    if docker exec postgres-replica pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
        echo "✅ Replica is ready!"
        break
    fi
    sleep 2
    if [ $i -eq 30 ]; then
        echo "❌ ERROR: Replica failed to start within 60 seconds"
        exit 1
    fi
done


# ──────────────────────────────────────────────────────
# 11. Start Starrocks MPP DWH
# ──────────────────────────────────────────────────────
echo "=== Starting StarRocks MPP DWH ==="
mkdir -p ./starrocks-data/fe ./starrocks-data/be
docker compose up -d starrocks

echo "Waiting for StarRocks FE..."
for i in {1..80}; do
    if curl -fsS "http://localhost:${STARROCKS_FE_HTTP_PORT:-8030}/api/bootstrap" >/dev/null 2>&1; then
        echo "✅ StarRocks FE is up!"
        break
    fi
    sleep 3
    if [ $i -eq 80 ]; then
        echo "❌ ERROR: StarRocks FE did not start"
        docker logs starrocks --tail 50
        exit 1
    fi
done

echo "Waiting for StarRocks BE to join FE..."
for i in {1..40}; do 
    ALIVE=$(docker exec starrocks mysql -h 127.0.0.1 -P 9030 -u root \
      --connect-timeout=5 -s -e "SHOW BACKENDS\G" 2>/dev/null \
      | grep -c "Alive: true" || echo "0")
    if [ "$ALIVE" -ge "1" ]; then
        echo "✅ StarRocks BE is alive!"
        break
    fi
    sleep 5
    if [ $i -eq 40 ]; then
        echo "❌ ERROR: StarRocks BE did not join"
        exit 1
    fi 
done

echo "Initializing StarRocks schema (dwh_detailed + presentation)..."
docker exec -i starrocks mysql -h 127.0.0.1 -P 9030 -u root \
    < ./dwh/ddl/001_starrocks_dwh_detailed.sql
echo "✅ StarRocks dwh_detailed schema initialized!"

docker exec -i starrocks mysql -h 127.0.0.1 -P 9030 -u root \
    < ./dwh/ddl/002_starrocks_presentation.sql
echo "✅ StarRocks presentation schema initialized"


# ──────────────────────────────────────────────────────
# 12. Start Kafka
# ──────────────────────────────────────────────────────
echo "=== Starting Kafka ==="
docker compose up -d kafka

echo "Waiting for Kafka broker to accept API..."
for i in {1..60}; do
    if docker exec kafka bash -c \
        "kafka-broker-api-versions --bootstrap-server localhost:9092 >/dev/null 2>&1"; then
        echo "✅ Kafka is reachable"
        break
    fi
    sleep 2
    if [ "$i" -eq 60 ]; then
        echo "❌ ERROR: Kafka did not ready"
        docker logs kafka --tail 50
        exit 1
    fi
done

echo "Waiting for Kafka topics API to be ready..."
for i in {1..30}; do
    if docker exec kafka kafka-topics --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
        echo "✅ Kafka topics API is ready!"
        break
    fi
    sleep 2
    if [ "$i" -eq 30 ]; then
        echo "❌ ERROR: Kafka topics API did not ready"
        exit 1
    fi
done


# ──────────────────────────────────────────────────────
# 13. Create Debezium internal topics
# ──────────────────────────────────────────────────────
echo "=== Creating Debezium internal topics ==="
docker exec kafka bash -lc "\
  kafka-topics --bootstrap-server localhost:9092 --create --replication-factor 1 \
    --partitions 1 --topic debezium_configs --config cleanup.policy=compact || true && \
  kafka-topics --bootstrap-server localhost:9092 --create --replication-factor 1 \
    --partitions 1 --topic debezium_offsets --config cleanup.policy=compact || true && \
  kafka-topics --bootstrap-server localhost:9092 --create --replication-factor 1 \
    --partitions 1 --topic debezium_statuses --config cleanup.policy=compact || true"


# ──────────────────────────────────────────────────────
# 14. Start Debezium + register connectors
# ──────────────────────────────────────────────────────
echo "=== Starting debezium ==="
docker compose up -d debezium

echo "Waiting for Debezium Connect REST to be available..."
for i in {1..60}; do
  if curl -fsS "http://localhost:${DEBEZIUM_PORT:-8083}/" >/dev/null 2>&1; then
    echo "✅ Debezium Connect is up"
    break
  fi
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "❌ ERROR: Debezium Connect did not start"
    docker logs debezium --tail 50
    exit 1
  fi
done

if [ -f ./debezium/register-connectors.sh ]; then
  echo "✅ Registering connectors via debezium/register-connectors.sh ..."
  chmod +x ./debezium/register-connectors.sh
  ./debezium/register-connectors.sh
else
  echo "❌ Skip registration: ./debezium/register-connectors.sh not found. You can register connectors manually or add the script."
fi


# ──────────────────────────────────────────────────────
# 15. Start DMP service
# ──────────────────────────────────────────────────────
echo "Starting DMP Service..."
docker compose up -d dmp-service
echo "✅ DMP Service is running"


# ──────────────────────────────────────────────────────
# 16. Initialize and start Airflow
# ──────────────────────────────────────────────────────
echo "=== Initializing Airflow ==="

docker compose up airflow-init
 
INIT_EXIT=$(docker inspect --format='{{.State.ExitCode}}' airflow-init 2>/dev/null || echo "1")
if [ "$INIT_EXIT" != "0" ]; then
    echo "❌ ERROR: Airflow init failed (exit code $INIT_EXIT)"
    docker logs airflow-init --tail 50
    exit 1
fi
echo "✅ Airflow DB initialized, admin user created"
 
echo "Starting Airflow scheduler and webserver..."
docker compose up -d airflow-scheduler airflow-webserver
 
echo "Waiting for Airflow webserver..."
for i in {1..40}; do
    curl -fsS "http://localhost:${AIRFLOW_PORT:-8080}/health" >/dev/null 2>&1 && echo "✅ Airflow webserver up!" && break
    sleep 5
    if [ $i -eq 40 ]; then
        echo "⚠️ WARNING: Airflow webserver took too long"
        break
    fi
done


# ──────────────────────────────────────────────────────
# 17. Start Metabase
# ──────────────────────────────────────────────────────
echo "=== Starting Metabase ==="
mkdir -p ./metabase-data
docker compose up -d metabase
 
echo "Waiting for Metabase..."
for i in {1..60}; do
    curl -fsS "http://localhost:${METABASE_PORT:-3000}/api/health" >/dev/null 2>&1 && echo "✅ Metabase up!" && break
    sleep 5
    if [ $i -eq 60 ]; then 
        echo "⚠️ WARNING: Metabase still starting"
        break
    fi
done


# ──────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────
echo ""
echo "==================================================================="
echo "                    SETUP COMPLETED SUCCESSFULLY"
echo "==================================================================="
echo ""
echo "  PostgreSQL Master:  postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_MASTER_PORT/postgres"
echo "  PostgreSQL Replica: postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_REPLICA_PORT/postgres"
echo "  StarRocks SQL:      mysql -h localhost -P ${STARROCKS_FE_MYSQL_PORT:-9030} -u root -D presentation"
echo ""
echo "  ┌─────────────────────────────────────────────────────────────┐"
echo "  │  Apache Airflow:  http://localhost:${AIRFLOW_PORT:-8080}    │"
echo "  │  Login: admin / admin                                       │"
echo "  ├─────────────────────────────────────────────────────────────┤"
echo "  │  Metabase BI:     http://localhost:${METABASE_PORT:-3000}   │"
echo "  │  Setup on first launch                                      │"
echo "  └─────────────────────────────────────────────────────────────┘"
echo ""
echo "  DAGs to enable in Airflow UI:"
echo "    - dm_purchase_analytics   (daily @ 06:00 UTC, full refresh)"
echo "    - dm_warehouse_delivery   (daily @ 07:00 UTC, incremental)"
echo ""
echo "  Metabase: connect as MySQL — host=starrocks, port=9030, user=root"
echo "==================================================================="
