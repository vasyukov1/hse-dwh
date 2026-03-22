#!/bin/bash
# =============================================================
# reinit_and_trigger.sh
# 1. Recreates presentation tables in StarRocks
# 2. Detects business dates available in source tables
# 3. Runs both DAGs via `airflow dags test` for deterministic checks
# =============================================================
set -euo pipefail

SR_PORT="${STARROCKS_FE_MYSQL_PORT:-9030}"
WAIT_FOR_DWH_SEC="${WAIT_FOR_DWH_SEC:-180}"

latest_purchase_date() {
    docker exec -i postgres-master psql -U postgres -d order_service_db -tAc \
        "SELECT MAX(DATE(order_date))::text FROM orders WHERE order_date IS NOT NULL;"
}

latest_delivery_business_date() {
    docker exec -i postgres-master psql -U postgres -d logistics_service_db -tAc \
        "SELECT MAX(DATE(dispatched_date))::text FROM shipments WHERE dispatched_date IS NOT NULL;"
}

add_day() {
    python3 - "$1" <<'PY'
from datetime import date, timedelta
import sys
print((date.fromisoformat(sys.argv[1]) + timedelta(days=1)).isoformat())
PY
}

source_order_items_count() {
    docker exec -i postgres-master psql -U postgres -d order_service_db -tAc \
        "SELECT COUNT(*) FROM order_items;"
}

source_dispatched_shipments_count() {
    docker exec -i postgres-master psql -U postgres -d logistics_service_db -tAc \
        "SELECT COUNT(*) FROM shipments WHERE dispatched_date IS NOT NULL;"
}

dwh_order_items_count() {
    docker exec -i starrocks mysql -h 127.0.0.1 -P "$SR_PORT" -u root -D dwh_detailed \
        --silent --skip-column-names -e "SELECT COUNT(*) FROM sat_order_items;"
}

dwh_dispatched_shipments_count() {
    docker exec -i starrocks mysql -h 127.0.0.1 -P "$SR_PORT" -u root -D dwh_detailed \
        --silent --skip-column-names -e "SELECT COUNT(*) FROM sat_shipments WHERE dispatched_date IS NOT NULL;"
}

wait_for_dwh_readiness() {
    local waited=0
    local interval=5
    local src_order_items src_shipments dwh_order_items dwh_shipments

    src_order_items="$(source_order_items_count | tr -d '[:space:]')"
    src_shipments="$(source_dispatched_shipments_count | tr -d '[:space:]')"

    echo ""
    echo "=== Step 2: Waiting for dwh_detailed readiness (up to ${WAIT_FOR_DWH_SEC}s) ==="

    while [ "$waited" -lt "$WAIT_FOR_DWH_SEC" ]; do
        dwh_order_items="$(dwh_order_items_count | tr -d '[:space:]')"
        dwh_shipments="$(dwh_dispatched_shipments_count | tr -d '[:space:]')"

        dwh_order_items="${dwh_order_items:-0}"
        dwh_shipments="${dwh_shipments:-0}"

        if [ "$dwh_order_items" -ge "${src_order_items:-0}" ] && [ "$dwh_shipments" -ge "${src_shipments:-0}" ]; then
            echo "✅ dwh_detailed is ready: sat_order_items=$dwh_order_items/$src_order_items, sat_shipments=$dwh_shipments/$src_shipments"
            return 0
        fi

        echo "  progress: sat_order_items=$dwh_order_items/$src_order_items, sat_shipments=$dwh_shipments/$src_shipments (${waited}s/${WAIT_FOR_DWH_SEC}s)"
        sleep "$interval"
        waited=$((waited + interval))
    done

    echo "⚠️  dwh_detailed is still catching up. DAGs will continue and fall back to source PostgreSQL if needed."
}

PURCHASE_LOGICAL_DATE="${1:-$(latest_purchase_date)}"
DELIVERY_BUSINESS_DATE="$(latest_delivery_business_date)"
DELIVERY_LOGICAL_DATE="${2:-$(add_day "$DELIVERY_BUSINESS_DATE")}"

echo "=== Step 1: Recreating presentation tables in StarRocks (port $SR_PORT) ==="
docker exec -i starrocks mysql -h 127.0.0.1 -P "$SR_PORT" -u root \
    < ./dwh/ddl/002_starrocks_presentation.sql
echo "✅ Presentation tables recreated."

wait_for_dwh_readiness

echo ""
echo "=== Step 3: Running Airflow DAG tests ==="
echo "  purchase logical date:  $PURCHASE_LOGICAL_DATE"
echo "  delivery business date: $DELIVERY_BUSINESS_DATE"
echo "  delivery logical date:  $DELIVERY_LOGICAL_DATE"

docker exec airflow-scheduler airflow dags test dm_purchase_analytics "$PURCHASE_LOGICAL_DATE"
docker exec airflow-scheduler airflow dags test dm_warehouse_delivery "$DELIVERY_LOGICAL_DATE"

echo ""
echo "=== Step 4: Row counts in presentation ==="
docker exec starrocks mysql -h 127.0.0.1 -P "$SR_PORT" -u root \
    --silent --skip-column-names -e "
    SELECT CONCAT('  dm_purchase_analytics: ', COUNT(*)) FROM presentation.dm_purchase_analytics
    UNION ALL
    SELECT CONCAT('  dm_warehouse_delivery: ', COUNT(*)) FROM presentation.dm_warehouse_delivery;"

echo ""
echo "=== Step 5: Sample rows ==="
docker exec starrocks mysql -h 127.0.0.1 -P "$SR_PORT" -u root -e "
    SELECT * FROM presentation.dm_purchase_analytics
    ORDER BY total_purchase_amount DESC
    LIMIT 3;

    SELECT * FROM presentation.dm_warehouse_delivery
    WHERE shipment_date = '${DELIVERY_BUSINESS_DATE}'
    ORDER BY order_count DESC
    LIMIT 3;"

echo ""
echo "=================================================================="
echo "  Airflow:   http://localhost:${AIRFLOW_PORT:-8080}  (admin/admin)"
echo "  Metabase:  http://localhost:${METABASE_PORT:-3000}"
echo "=================================================================="
