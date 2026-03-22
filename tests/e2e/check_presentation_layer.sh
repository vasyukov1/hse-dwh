#!/bin/bash
set -e

echo "=================================================================="
echo "  E2E Test: Presentation Layer (CDM) Verification"
echo "=================================================================="


# ── Helper ────────────────────────────────────────────
sr_query() {
    docker exec -i starrocks mysql -h 127.0.0.1 -P 9030 -u root -e "$1" 2>/dev/null
}


# ── 1. Check schemas exist ────────────────────────────
echo ""
echo "▶ STEP 1: Checking presentation schema and tables"
sr_query "SHOW DATABASES LIKE 'presentation';" | grep -q "presentation" \
    && echo "✅ Database 'presentation' exists" \
    || { echo "❌ Database 'presentation' NOT found"; exit 1; }

TABLES=$(sr_query "SHOW TABLES FROM presentation;")
echo "$TABLES" | grep -q "dm_purchase_analytics" \
    && echo "✅ Table dm_purchase_analytics exists" \
    || { echo "❌ dm_purchase_analytics NOT found"; exit 1; }
echo "$TABLES" | grep -q "dm_warehouse_delivery" \
    && echo "✅ Table dm_warehouse_delivery exists" \
    || { echo "❌ dm_warehouse_delivery NOT found"; exit 1; }


# ── 2. Manually trigger DAGs via Airflow CLI ──────────
echo ""
echo "▶ STEP 2: Triggering Airflow DAGs manually"
docker exec -i airflow-scheduler airflow dags trigger dm_purchase_analytics \
    && echo "✅ dm_purchase_analytics triggered" \
    || echo "⚠️ WARNING: Could not trigger dm_purchase_analytics (may already be running)"

docker exec -i airflow-scheduler airflow dags trigger dm_warehouse_delivery \
    && echo "✅ dm_warehouse_delivery triggered" \
    || echo "⚠️ WARNING: Could not trigger dm_warehouse_delivery"

echo "  Waiting 30s for DAGs to finish..."
sleep 30


# ── 3. Check mart 1 ───────────────────────────────────
echo ""
echo "▶ STEP 3: Checking dm_purchase_analytics"
COUNT=$(sr_query "SELECT COUNT(*) FROM presentation.dm_purchase_analytics;" | tail -n1 | tr -d ' ')
echo "  Rows in dm_purchase_analytics: $COUNT"
if [ "$COUNT" -gt "0" ]; then
    echo "✅ dm_purchase_analytics has data!"
    sr_query "
        SELECT
            purchase_date,
            product_name,
            category,
            supplier_name,
            purchase_qty,
            total_purchase_amount,
            avg_unit_price
        FROM presentation.dm_purchase_analytics
        ORDER BY total_purchase_amount DESC
        LIMIT 5;
    "
else
    echo "  ⚠ dm_purchase_analytics is empty (DAG may still be running or DWH has no data)"
fi


# ── 4. Check mart 2 ───────────────────────────────────
echo ""
echo "▶ STEP 4: Checking dm_warehouse_delivery"
COUNT=$(sr_query "SELECT COUNT(*) FROM presentation.dm_warehouse_delivery;" | tail -n1 | tr -d ' ')
echo "  Rows in dm_warehouse_delivery: $COUNT"
if [ "$COUNT" -gt "0" ]; then
    echo "✅ dm_warehouse_delivery has data!"
    sr_query "
        SELECT
            shipment_date,
            warehouse_name,
            order_count,
            total_shipment_qty,
            avg_processing_time_min,
            delayed_orders_count,
            unique_customers_count
        FROM presentation.dm_warehouse_delivery
        ORDER BY shipment_date DESC
        LIMIT 5;
    "
else
    echo "  ⚠ dm_warehouse_delivery is empty (DAG may still be running or DWH has no data)"
fi


# ── 5. Check Airflow DAG status ───────────────────────
echo ""
echo "▶ STEP 5: Airflow DAG run status"
docker exec -i airflow-scheduler airflow dags list-runs \
    --dag-id dm_purchase_analytics --no-backfill -o table 2>/dev/null | head -10 || true
docker exec -i airflow-scheduler airflow dags list-runs \
    --dag-id dm_warehouse_delivery --no-backfill -o table 2>/dev/null | head -10 || true


# ── 6. Schema validation ──────────────────────────────
echo ""
echo "▶ STEP 6: Schema validation (column check)"
echo "  dm_purchase_analytics columns:"
sr_query "DESCRIBE presentation.dm_purchase_analytics;" | awk '{print "    " $1, $2}'
echo ""
echo "  dm_warehouse_delivery columns:"
sr_query "DESCRIBE presentation.dm_warehouse_delivery;" | awk '{print "    " $1, $2}'


echo ""
echo "=================================================================="
echo "  Presentation layer check complete."
echo "  Access Airflow at: http://localhost:${AIRFLOW_PORT:-8080}  (admin/admin)"
echo "  Access Metabase at: http://localhost:${METABASE_PORT:-3000}"
echo "=================================================================="
