#!/bin/bash
set -euo pipefail

# debezium/register-connectors.sh
# Idempotent connector registration for Debezium (Kafka Connect).
# Requires: curl, jq
# Usage: ./debezium/register-connectors.sh

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
WAIT_RETRY="${WAIT_RETRY:-300}"

printf 'Waiting for Debezium Connect at %s ...\n' "$CONNECT_URL"
i=0
until curl -fsS "${CONNECT_URL}/" >/dev/null 2>&1; do
  i=$((i+1))
  if [ "$i" -gt "$WAIT_RETRY" ]; then
    echo "Connect didn't appear after $WAIT_RETRY tries, aborting."
    exit 1
  fi
  sleep 2
done
echo "Debezium Connect is up."

# helper: create or update connector
create_or_update() {
  local name="$1"
  local body="$2"            # full body: {"name":"...","config":{...}}
  local exists_http
  exists_http=$(curl -s -o /dev/null -w "%{http_code}" "${CONNECT_URL}/connectors/${name}" || echo "000")

  if [ "$exists_http" = "200" ]; then
    echo "Connector ${name} exists -> updating config (PUT)..."
    # Extract only the "config" object for PUT /connectors/{name}/config
    config_json=$(echo "$body" | jq -c '.config')
    if [ -z "$config_json" ] || [ "$config_json" = "null" ]; then
      echo "ERROR: body for connector ${name} does not contain .config"
      exit 1
    fi

    resp=$(curl -s -w "\n%{http_code}" -X PUT "${CONNECT_URL}/connectors/${name}/config" \
      -H "Content-Type: application/json" -d "${config_json}")
    http=$(echo "$resp" | tail -n1)
    body_out=$(echo "$resp" | sed '$d')

    if [ "$http" != "200" ] && [ "$http" != "201" ]; then
      echo "Failed to update connector ${name}, http=$http"
      echo "Response body:"
      echo "$body_out"
      exit 1
    else
      echo "Connector ${name} updated."
      echo "$body_out" | jq .
    fi

  elif [ "$exists_http" = "404" ]; then
    echo "Connector ${name} not found -> creating (POST)..."
    resp=$(curl -s -w "\n%{http_code}" -X POST "${CONNECT_URL}/connectors" \
      -H "Content-Type: application/json" -d "${body}")
    http=$(echo "$resp" | tail -n1)
    body_out=$(echo "$resp" | sed '$d')

    if [ "$http" != "201" ] && [ "$http" != "200" ]; then
      echo "Failed to create connector ${name}, http=$http"
      echo "Response body:"
      echo "$body_out"
      exit 1
    else
      echo "Connector ${name} created."
      echo "$body_out" | jq .
    fi

  else
    echo "Unexpected HTTP code checking connector ${name}: ${exists_http}"
    echo "Response from server may be unhealthy. Dumping /connectors response for inspection:"
    curl -s "${CONNECT_URL}/connectors" || true
    exit 1
  fi
}

# -------- CONNECTOR BODIES (JSON) --------
# Note: keep these JSON blocks compact and valid; values must be strings.

USER_BODY='{
  "name":"user-service-connector",
  "config":{
    "connector.class":"io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max":"1",
    "plugin.name":"pgoutput",
    "topic.prefix":"user_service",
    "database.hostname":"postgres-master",
    "database.port":"5432",
    "database.user":"dbzuser",
    "database.password":"dbzpass",
    "database.dbname":"user_service_db",
    "publication.name":"dbz_pub_user_service",
    "publication.autocreate.mode":"disabled",
    "slot.name":"debezium_user_service",
    "table.include.list":"public.users,public.user_addresses,public.user_status_history",
    "snapshot.mode":"initial",
    "heartbeat.interval.ms":"0",
    "time.precision.mode": "connect",
    "decimal.handling.mode": "string"
  }
}'

ORDER_BODY='{
  "name":"order-service-connector",
  "config":{
    "connector.class":"io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max":"1",
    "plugin.name":"pgoutput",
    "topic.prefix":"order_service",
    "database.hostname":"postgres-master",
    "database.port":"5432",
    "database.user":"dbzuser",
    "database.password":"dbzpass",
    "database.dbname":"order_service_db",
    "publication.name":"dbz_pub_order_service",
    "publication.autocreate.mode":"disabled",
    "slot.name":"debezium_order_service",
    "table.include.list":"public.orders,public.products,public.order_items,public.order_status_history",
    "snapshot.mode":"initial",
    "heartbeat.interval.ms":"0",
    "time.precision.mode": "connect",
    "decimal.handling.mode": "string"
  }
}'

LOGISTICS_BODY='{
  "name":"logistics-service-connector",
  "config":{
    "connector.class":"io.debezium.connector.postgresql.PostgresConnector",
    "tasks.max":"1",
    "plugin.name":"pgoutput",
    "topic.prefix":"logistics_service",
    "database.hostname":"postgres-master",
    "database.port":"5432",
    "database.user":"dbzuser",
    "database.password":"dbzpass",
    "database.dbname":"logistics_service_db",
    "publication.name":"dbz_pub_logistics_service",
    "publication.autocreate.mode":"disabled",
    "slot.name":"debezium_logistics_service",
    "table.include.list":"public.warehouses,public.pickup_points,public.shipments,public.shipment_movements,public.shipment_status_history",
    "snapshot.mode":"initial",
    "heartbeat.interval.ms":"0",
    "time.precision.mode": "connect",
    "decimal.handling.mode": "string"
  }
}'

# -------- REGISTER --------
create_or_update "user-service-connector" "$USER_BODY"
create_or_update "order-service-connector" "$ORDER_BODY"
create_or_update "logistics-service-connector" "$LOGISTICS_BODY"

echo "All connectors processed."
