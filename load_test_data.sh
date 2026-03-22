#!/bin/bash
# =============================================================
# load_test_data.sh
# Loads all CSV files from test_data/ into PostgreSQL source DBs
# in the correct FK-dependency order.
#
# Usage:
#   ./load_test_data.sh                  # uses ./test_data/
#   ./load_test_data.sh /path/to/csvs    # custom dir
#
# After loading, Debezium CDC streams changes to Kafka → DMP → StarRocks.
# =============================================================
set -e

DATA_DIR="${1:-./test_data}"
MASTER="postgres-master"
PG_USER="postgres"
WAIT_PIPELINE_SEC="${WAIT_PIPELINE_SEC:-180}"   # max seconds to wait for CDC pipeline after load

# ── colours ──────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; }

# ── guard ─────────────────────────────────────────────────────
if [ ! -d "$DATA_DIR" ]; then
    err "Directory '$DATA_DIR' not found."
    echo "  Usage: $0 [path_to_csv_dir]"
    echo "  Expected files:"
    echo "    user_service_users.csv"
    echo "    user_service_user_addresses.csv"
    echo "    user_service_user_status_history.csv"
    echo "    order_service_products.csv"
    echo "    order_service_orders.csv"
    echo "    order_service_order_items.csv"
    echo "    order_service_order_status_history.csv"
    echo "    logistics_service_warehouses.csv"
    echo "    logistics_service_pickup_points.csv"
    echo "    logistics_service_shipments.csv"
    echo "    logistics_service_shipment_movements.csv"
    echo "    logistics_service_shipment_status_history.csv"
    exit 1
fi

echo "========================================================"
echo "  Loading test data from: $DATA_DIR"
echo "========================================================"

# ── Copy all CSVs into the container once ─────────────────────
echo ""
echo "▶ Copying CSV files into $MASTER..."
CSV_COUNT=0
for f in "$DATA_DIR"/*.csv; do
    [ -f "$f" ] || continue
    docker cp "$f" "$MASTER:/tmp/$(basename "$f")" 2>/dev/null
    CSV_COUNT=$((CSV_COUNT + 1))
done
ok "Copied $CSV_COUNT file(s) to /tmp/ inside $MASTER"

# ── Core loader ───────────────────────────────────────────────
# load_table DB TABLE FILENAME
#   Uses server-side COPY (file already in container).
#   Column list is read directly from the CSV header, so it works
#   even when the table has extra SERIAL/generated columns.
load_table() {
    local db="$1"
    local table="$2"
    local csv_name="$3"          # just the basename, e.g. user_service_users.csv
    local container_path="/tmp/$csv_name"

    # Check file exists in container
    if ! docker exec "$MASTER" test -f "$container_path" 2>/dev/null; then
        warn "Skipping $db.$table — file not found: $csv_name"
        return 0
    fi

    # Read header (strip Windows \r)
    local cols
    cols=$(docker exec "$MASTER" bash -c "head -1 '$container_path' | tr -d '\r'")
    if [ -z "$cols" ]; then
        warn "Skipping $db.$table — could not read header from $csv_name"
        return 0
    fi

    echo "  ↳ $db.$table  ←  $csv_name"

    # Server-side COPY: fast, no client overhead.
    # NULL '' maps empty CSV fields to SQL NULL (handles optional FKs).
    local rows
    rows=$(docker exec "$MASTER" psql -U "$PG_USER" -d "$db" -t -c \
        "COPY $table ($cols)
         FROM '$container_path'
         WITH (FORMAT CSV, HEADER true, NULL '')" 2>&1)

    if echo "$rows" | grep -qi "error"; then
        warn "  Some rows skipped for $db.$table: $rows"
    else
        local n
        n=$(printf '%s\n' "$rows" | grep -Eo '[0-9]+' | head -1)
        ok "  Loaded ${n:-?} rows → $db.$table"
    fi
}

pg_scalar() {
    local db="$1"
    local sql="$2"
    docker exec "$MASTER" psql -U "$PG_USER" -d "$db" -tAc "$sql" 2>/dev/null | tr -d '[:space:]'
}

sr_scalar() {
    local db="$1"
    local sql="$2"
    docker exec starrocks mysql -h 127.0.0.1 -P 9030 -u root -D "$db" \
        --silent --skip-column-names -e "$sql" 2>/dev/null | tail -n1 | tr -d '[:space:]'
}

wait_for_pipeline() {
    local waited=0
    local interval=5
    local src_order_items src_shipments dwh_order_items dwh_shipments

    src_order_items=$(pg_scalar "order_service_db" "SELECT COUNT(*) FROM order_items;")
    src_shipments=$(pg_scalar "logistics_service_db" "SELECT COUNT(*) FROM shipments WHERE dispatched_date IS NOT NULL;")

    echo ""
    echo "⏳ Waiting up to ${WAIT_PIPELINE_SEC}s for Debezium → Kafka → DMP → StarRocks..."

    while [ "$waited" -lt "$WAIT_PIPELINE_SEC" ]; do
        dwh_order_items=$(sr_scalar "dwh_detailed" "SELECT COUNT(*) FROM sat_order_items;")
        dwh_shipments=$(sr_scalar "dwh_detailed" "SELECT COUNT(*) FROM sat_shipments WHERE dispatched_date IS NOT NULL;")

        dwh_order_items="${dwh_order_items:-0}"
        dwh_shipments="${dwh_shipments:-0}"

        if [ "$dwh_order_items" -ge "${src_order_items:-0}" ] && [ "$dwh_shipments" -ge "${src_shipments:-0}" ]; then
            ok "CDC pipeline is ready: sat_order_items=$dwh_order_items/$src_order_items, sat_shipments=$dwh_shipments/$src_shipments"
            return 0
        fi

        echo "  progress: sat_order_items=$dwh_order_items/$src_order_items, sat_shipments=$dwh_shipments/$src_shipments (${waited}s/${WAIT_PIPELINE_SEC}s)"
        sleep "$interval"
        waited=$((waited + interval))
    done

    warn "CDC pipeline is still catching up. Airflow DAGs can still run because they fall back to source PostgreSQL."
    return 0
}

# ── user_service_db ──────────────────────────────────────────
echo ""
echo "▶ user_service_db"
# Load order matters: users first (no deps), then dependents
load_table "user_service_db" "users" \
    "user_service_users.csv"
load_table "user_service_db" "user_addresses" \
    "user_service_user_addresses.csv"
load_table "user_service_db" "user_status_history" \
    "user_service_user_status_history.csv"

# ── order_service_db ─────────────────────────────────────────
echo ""
echo "▶ order_service_db"
# products and orders have no internal deps; order_items needs both
load_table "order_service_db" "products" \
    "order_service_products.csv"
load_table "order_service_db" "orders" \
    "order_service_orders.csv"
load_table "order_service_db" "order_items" \
    "order_service_order_items.csv"
load_table "order_service_db" "order_status_history" \
    "order_service_order_status_history.csv"

# ── logistics_service_db ─────────────────────────────────────
echo ""
echo "▶ logistics_service_db"
# warehouses + pickup_points before shipments (FK deps)
load_table "logistics_service_db" "warehouses" \
    "logistics_service_warehouses.csv"
load_table "logistics_service_db" "pickup_points" \
    "logistics_service_pickup_points.csv"
load_table "logistics_service_db" "shipments" \
    "logistics_service_shipments.csv"
load_table "logistics_service_db" "shipment_movements" \
    "logistics_service_shipment_movements.csv"
load_table "logistics_service_db" "shipment_status_history" \
    "logistics_service_shipment_status_history.csv"

# ── Row counts summary ────────────────────────────────────────
echo ""
echo "========================================================"
echo "  Row counts in PostgreSQL"
echo "========================================================"
for db in user_service_db order_service_db logistics_service_db; do
    echo "  [$db]"
    docker exec "$MASTER" psql -U "$PG_USER" -d "$db" -t -c "
        SELECT '    ' || relname || ': ' || n_live_tup || ' rows'
        FROM pg_stat_user_tables
        WHERE n_live_tup > 0
        ORDER BY relname;" 2>/dev/null || true
done

# ── Wait for CDC pipeline ─────────────────────────────────────
wait_for_pipeline

# ── StarRocks counts ──────────────────────────────────────────
echo ""
echo "========================================================"
echo "  Row counts in StarRocks (dwh_detailed)"
echo "========================================================"
docker exec starrocks mysql -h 127.0.0.1 -P 9030 -u root -D dwh_detailed \
    --silent --skip-column-names -e "
    SELECT CONCAT('  hub_users:              ', COUNT(*)) FROM hub_users
    UNION ALL SELECT CONCAT('  hub_orders:             ', COUNT(*)) FROM hub_orders
    UNION ALL SELECT CONCAT('  hub_products:           ', COUNT(*)) FROM hub_products
    UNION ALL SELECT CONCAT('  hub_shipments:          ', COUNT(*)) FROM hub_shipments
    UNION ALL SELECT CONCAT('  hub_warehouses:         ', COUNT(*)) FROM hub_warehouses
    UNION ALL SELECT CONCAT('  hub_pickup_points:      ', COUNT(*)) FROM hub_pickup_points
    UNION ALL SELECT CONCAT('  sat_order_items:        ', COUNT(*)) FROM sat_order_items
    UNION ALL SELECT CONCAT('  sat_shipments:          ', COUNT(*)) FROM sat_shipments
    UNION ALL SELECT CONCAT('  sat_shipment_movements: ', COUNT(*)) FROM sat_shipment_movements;" \
    2>/dev/null || warn "StarRocks not reachable or still loading — try again in a moment."

echo ""
echo "========================================================"
echo "  Next steps"
echo "========================================================"
echo "  Trigger Airflow DAGs (or wait for scheduled run):"
echo "    http://localhost:8080  (admin / admin)"
echo "    DAG 1: dm_purchase_analytics  — full refresh"
echo "    DAG 2: dm_warehouse_delivery  — incremental"
echo ""
echo "  Or trigger via CLI:"
echo "    docker exec airflow-scheduler airflow dags trigger dm_purchase_analytics"
echo "    docker exec airflow-scheduler airflow dags trigger dm_warehouse_delivery"
echo ""
echo "  Explore results in Metabase:"
echo "    http://localhost:3000"
echo "    Connect as MySQL: host=starrocks, port=9030, user=root, db=presentation"
echo "========================================================"
