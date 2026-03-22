#!/bin/bash
# =============================================================
# reinit_and_trigger.sh
# 1. Пересоздаёт таблицы presentation (DROP + CREATE)
# 2. Ждёт загрузки DAG-ов в Airflow
# 3. Запускает оба DAG-а вручную
# =============================================================
set -e

SR_PORT="${STARROCKS_FE_MYSQL_PORT:-9031}"
AF_PORT="${AIRFLOW_PORT:-8080}"
AF_USER="${AIRFLOW_ADMIN_USER:-admin}"
AF_PASS="${AIRFLOW_ADMIN_PASSWORD:-admin}"

echo "=== Step 1: Recreating presentation tables in StarRocks ==="

if [ -f "./dwh/ddl/002_starrocks_presentation.sql" ]; then
    docker exec -i starrocks mysql -h 127.0.0.1 -P "$SR_PORT" -u root \
        < ./dwh/ddl/002_starrocks_presentation.sql
    echo "  Presentation tables recreated."
else
    echo "  File dwh/ddl/002_starrocks_presentation.sql not found!"
    exit 1
fi

echo ""
echo "=== Step 2: Verifying DAG file is in place ==="
if [ ! -f "./airflow/dags/dwh_refresh.py" ]; then
    echo "  ERROR: airflow/dags/dwh_refresh.py not found!"
    echo "  Copy the DAG file there and restart airflow-scheduler."
    exit 1
fi
echo "  DAG file found: airflow/dags/dwh_refresh.py"

echo ""
echo "=== Step 3: Waiting for Airflow scheduler to load DAGs (up to 60s) ==="
for i in $(seq 1 12); do
    # Check if DAG is registered via REST API
    STATUS=$(curl -s -u "$AF_USER:$AF_PASS" \
        "http://localhost:$AF_PORT/api/v1/dags/dm_purchase_analytics" \
        2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dag_id',''))" \
        2>/dev/null || echo "")

    if [ "$STATUS" = "dm_purchase_analytics" ]; then
        echo "  DAGs loaded by Airflow!"
        break
    fi
    echo "  Waiting... ($((i*5))s)"
    sleep 5
    if [ "$i" -eq 12 ]; then
        echo "  WARNING: DAGs still not loaded. Trying to trigger anyway..."
    fi
done

echo ""
echo "=== Step 4: Triggering DAGs via Airflow REST API ==="

trigger_dag() {
    local dag_id="$1"
    local today
    today=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    echo "  Triggering $dag_id ..."
    RESP=$(curl -s -w "\n%{http_code}" \
        -u "$AF_USER:$AF_PASS" \
        -X POST "http://localhost:$AF_PORT/api/v1/dags/$dag_id/dagRuns" \
        -H "Content-Type: application/json" \
        -d "{\"logical_date\": \"$today\"}" 2>/dev/null)

    HTTP=$(echo "$RESP" | tail -1)
    BODY=$(echo "$RESP" | head -1)

    if [ "$HTTP" = "200" ] || [ "$HTTP" = "201" ]; then
        echo "  OK: $dag_id triggered (HTTP $HTTP)"
    else
        echo "  WARNING: HTTP $HTTP for $dag_id"
        echo "  $BODY"
    fi
}

trigger_dag "dm_purchase_analytics"
trigger_dag "dm_warehouse_delivery"

echo ""
echo "=== Step 5: Waiting 30s for DAGs to complete ==="
sleep 30

echo ""
echo "=== Step 6: Row counts in presentation ==="
docker exec starrocks mysql -h 127.0.0.1 -P "$SR_PORT" -u root -D presentation -s -e "
    SELECT 'dm_purchase_analytics',  COUNT(*) FROM dm_purchase_analytics
    UNION ALL
    SELECT 'dm_warehouse_delivery',  COUNT(*) FROM dm_warehouse_delivery;" 2>/dev/null \
    || echo "  Could not query StarRocks"

echo ""
echo "=== Step 7: Check Airflow DAG run status ==="
for dag in dm_purchase_analytics dm_warehouse_delivery; do
    echo "  [$dag]:"
    curl -s -u "$AF_USER:$AF_PASS" \
        "http://localhost:$AF_PORT/api/v1/dags/$dag/dagRuns?limit=1&order_by=-start_date" \
        2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    runs = data.get('dag_runs', [])
    if runs:
        r = runs[0]
        print(f'    state={r.get(\"state\")}, start={r.get(\"start_date\")}, end={r.get(\"end_date\")}')
    else:
        print('    No runs found')
except:
    print('    Could not parse response')
" 2>/dev/null || echo "    Could not fetch run info"
done

echo ""
echo "==================================================================="
echo "  Airflow:  http://localhost:$AF_PORT  (${AF_USER}/${AF_PASS})"
echo "  Metabase: http://localhost:${METABASE_PORT:-3000}"
echo "  StarRocks: mysql -h 127.0.0.1 -P $SR_PORT -u root -D presentation"
echo "==================================================================="