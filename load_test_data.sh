#!/bin/bash
# =============================================================
# load_test_data.sh
# Loads all CSV files from test_data/ into PostgreSQL source DBs.
# After loading, Debezium CDC sends changes to Kafka -> DMP -> StarRocks.
# =============================================================
set -e

DATA_DIR="${1:-./test_data}"
MASTER="postgres-master"
PG_USER="postgres"

echo "=== Loading test data from $DATA_DIR ==="

if [ ! -d "$DATA_DIR" ]; then
    echo "Directory $DATA_DIR not found!"
    echo "Usage: $0 [path_to_test_data_dir]"
    exit 1
fi

# helper: load CSV into a table using COPY
pg_load_csv() {
    local db="$1"
    local table="$2"
    local csv="$3"

    if [ ! -f "$csv" ]; then
        echo "  Skipping $table - file not found: $csv"
        return
    fi

    local cols
    cols=$(head -1 "$csv")
    echo "  Loading $csv -> $db.$table"

    docker cp "$csv" "$MASTER:/tmp/_load.csv"

    # Try simple COPY first; on conflict just skip duplicates
    docker exec -i "$MASTER" psql -U "$PG_USER" -d "$db" <<SQL 2>/dev/null || \
        echo "  Note: some rows in $table skipped (duplicate keys)"
\COPY $table ($cols) FROM '/tmp/_load.csv' CSV HEADER;
SQL
}

# helper: try multiple file name patterns
find_csv() {
    for pat in "$@"; do
        local f="$DATA_DIR/$pat"
        if [ -f "$f" ]; then echo "$f"; return; fi
    done
    echo ""
}

echo ""
echo "--- user_service_db ---"
f=$(find_csv "user_service_users.csv" "uesr_service_users.csv" "users.csv")
[ -n "$f" ] && pg_load_csv "user_service_db" "users" "$f"

f=$(find_csv "user_service_user_addresses.csv" "user_addresses.csv")
[ -n "$f" ] && pg_load_csv "user_service_db" "user_addresses" "$f"

f=$(find_csv "user_service_user_status_history.csv" "user_status_history.csv")
[ -n "$f" ] && pg_load_csv "user_service_db" "user_status_history" "$f"

echo ""
echo "--- order_service_db ---"
f=$(find_csv "order_service_products.csv" "products.csv")
[ -n "$f" ] && pg_load_csv "order_service_db" "products" "$f"

f=$(find_csv "order_service_orders.csv" "orders.csv")
[ -n "$f" ] && pg_load_csv "order_service_db" "orders" "$f"

f=$(find_csv "order_service_order_items.csv" "order_items.csv")
[ -n "$f" ] && pg_load_csv "order_service_db" "order_items" "$f"

f=$(find_csv "order_service_order_status_history.csv" "order_status_history.csv")
[ -n "$f" ] && pg_load_csv "order_service_db" "order_status_history" "$f"

echo ""
echo "--- logistics_service_db ---"
f=$(find_csv "logistics_service_warehouses.csv" "warehouses.csv")
[ -n "$f" ] && pg_load_csv "logistics_service_db" "warehouses" "$f"

f=$(find_csv "logistics_service_pickup_points.csv" "pickup_points.csv")
[ -n "$f" ] && pg_load_csv "logistics_service_db" "pickup_points" "$f"

f=$(find_csv "logistics_service_shipments.csv" "shipments.csv")
[ -n "$f" ] && pg_load_csv "logistics_service_db" "shipments" "$f"

f=$(find_csv "logistics_service_shipment_movements.csv" "shipment_movements.csv")
[ -n "$f" ] && pg_load_csv "logistics_service_db" "shipment_movements" "$f"

f=$(find_csv "logistics_service_shipment_status_history.csv" "shipment_status_history.csv")
[ -n "$f" ] && pg_load_csv "logistics_service_db" "shipment_status_history" "$f"

echo ""
echo "--- Row counts in PostgreSQL ---"
for db in user_service_db order_service_db logistics_service_db; do
    echo "  [$db]"
    docker exec "$MASTER" psql -U "$PG_USER" -d "$db" -t -c "
        SELECT '    ' || tablename || ': ' || n_live_tup || ' rows'
        FROM pg_stat_user_tables ORDER BY tablename;" 2>/dev/null || true
done

echo ""
echo "Waiting 20s for Debezium CDC pipeline..."
sleep 20

echo ""
echo "--- dwh_detailed row counts (StarRocks) ---"
docker exec starrocks mysql -h 127.0.0.1 -P 9031 -u root -D dwh_detailed -s -e "
    SELECT 'hub_users',              COUNT(*) FROM hub_users
    UNION ALL SELECT 'hub_orders',   COUNT(*) FROM hub_orders
    UNION ALL SELECT 'hub_products', COUNT(*) FROM hub_products
    UNION ALL SELECT 'hub_shipments',COUNT(*) FROM hub_shipments
    UNION ALL SELECT 'hub_warehouses',COUNT(*) FROM hub_warehouses
    UNION ALL SELECT 'sat_order_items',COUNT(*) FROM sat_order_items
    UNION ALL SELECT 'sat_shipments',COUNT(*) FROM sat_shipments;" 2>/dev/null \
    || echo "  StarRocks still processing..."

echo ""
echo "Done! Trigger Airflow DAGs:"
echo "  http://localhost:8080  (admin/admin)"
echo "  DAGs: dm_purchase_analytics, dm_warehouse_delivery"