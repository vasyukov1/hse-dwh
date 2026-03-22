#!/bin/bash
set -e

echo "=== Loading test data ==="

DATA_DIR="./test_data"

# Проверяем наличие файлов
if [ ! -d "$DATA_DIR" ]; then
    echo "Error: test_data directory not found!"
    echo "Download test data from: https://clck.ru/3QCYgU"
    echo "And extract to ./test_data/"
    exit 1
fi

# Функция для загрузки CSV с указанием колонок
load_csv() {
    local db=$1
    local table=$2
    local file=$3
    local columns=$4  # Необязательный параметр - список колонок
    
    if [ -f "$file" ]; then
        rows_before=$(docker exec postgres-master psql -U postgres -d "$db" -t -c "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "0")
        echo "Loading $table from $(basename $file)..."
        
        if [ -n "$columns" ]; then
            # Загрузка с указанием колонок
            docker exec -i postgres-master psql -U postgres -d "$db" -c "\copy $table($columns) FROM STDIN WITH CSV HEADER" < "$file"
        else
            # Загрузка без указания колонок
            docker exec -i postgres-master psql -U postgres -d "$db" -c "\copy $table FROM STDIN WITH CSV HEADER" < "$file"
        fi
        
        rows_after=$(docker exec postgres-master psql -U postgres -d "$db" -t -c "SELECT COUNT(*) FROM $table;")
        loaded=$((rows_after - rows_before))
        echo "✓ Loaded $loaded rows into $table"
    else
        echo "⚠️  File not found: $(basename $file)"
    fi
}

echo "1. Loading order_service_db..."
load_csv "order_service_db" "orders" "$DATA_DIR/order_service_orders.csv" \
    "order_external_id,user_external_id,order_number,order_date,status,subtotal,tax_amount,shipping_cost,discount_amount,total_amount,currency,delivery_address_external_id,delivery_type,expected_delivery_date,actual_delivery_date,payment_method,payment_status,effective_from,effective_to,is_current,created_at,updated_at,created_by,updated_by"

echo ""
echo "=== Data loaded successfully! ==="