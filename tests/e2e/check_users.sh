#!/bin/bash
set -e

CSV_FILE="tests/data/uesr_service_users.csv"

if [ ! -f "$CSV_FILE" ]; then
    echo "File $CSV_FILE does not found"
    exit 1
fi


echo "=========================================================="
echo "▶ ШАГ 1: Вставляем тестовые данные в Master DB"
echo "=========================================================="
INSETR_SQL=""
ROW_NUM=0
FIRST_UUID=""

while IFS=',' read -r user_external_id email first_name last_name phone \
        date_of_birth registration_date status effective_from effective_to \
        is_current created_at updated_at created_by updated_by; do
    [ "$user_external_id" = "user_external_id" ] && continue
    ROW_NUM=$((ROW_NUM + 1))
    [ $ROW_NUM -eq 1 ] && FIRST_UUID="$user_external_id"

    email="${email//\'/\'\'}"
    first_name="${first_name//\'/\'\'}"
    last_name="${last_name//\'/\'\'}"
    # phone="${phone//\'/\'\'}"
    # status="${status//\'/\'\'}"
    # created_by="${created_by//\'/\'\'}"
    # updated_by="${updated_by//\'/\'\'}"

    INSERT_SQL+="
INSERT INTO users (
    user_external_id, email, first_name, last_name, phone,
    date_of_birth, registration_date, status,
    effective_from, effective_to, is_current,
    created_at, updated_at, created_by, updated_by
) VALUES (
    '$user_external_id', '$email', '$first_name', '$last_name', '$phone',
    '$date_of_birth', '$registration_date', '$status',
    '$effective_from', '$effective_to', $is_current,
    '$created_at', '$updated_at', '$created_by', '$updated_by'
) ON CONFLICT (user_external_id) DO NOTHING;"
done < "$CSV_FILE"

if [ $ROW_NUM -eq 0 ]; then
    echo "There are no data in CSV"
    exit 1
fi

echo "Found rows: $ROW_NUM. First UUID: $FIRST_UUID"
docker exec -i postgres-master psql -U postgres -d user_service_db <<EOF
$INSERT_SQL
EOF

echo "Данные вставлены. Ждем 5 секунд для прохождения всего пайплайна..."
sleep 5


echo -e "\n=========================================================="
echo "▶ ШАГ 2: Проверяем физическую репликацию (Replica DB)"
echo "=========================================================="
docker exec -i postgres-replica psql -U postgres -d user_service_db -c \
    "SELECT user_external_id, email, first_name FROM users WHERE user_external_id = '$FIRST_UUID';"


echo -e "\n=========================================================="
echo "▶ ШАГ 3: Проверяем, что событие попало в Kafka (Debezium)"
echo "=========================================================="

docker exec -i kafka kafka-console-consumer \
    --bootstrap-server localhost:9092 \
    --topic user_service.public.users \
    --from-beginning --max-messages 1 --timeout-ms 5000 \
  | grep -o '"email":"zaharkudrjavtsev@example.net"' \
  || echo "Сообщение не найдено"


echo -e "\n=========================================================="
echo "▶ ШАГ 4: Проверяем Хаб в StarRocks (hub_users)"
echo "=========================================================="
docker exec -i starrocks mysql -h 127.0.0.1 -P 9030 -u root -D dwh_detailed \
  -e "SELECT hk_users, user_external_id, load_dt, record_source
      FROM hub_users
      WHERE user_external_id = '$FIRST_UUID';"


echo -e "\n=========================================================="
echo "▶ ШАГ 5: Проверяем Сателлит в StarRocks (sat_users)"
echo "=========================================================="
docker exec -i starrocks mysql -h 127.0.0.1 -P 9030 -u root -D dwh_detailed \
  -e "SELECT hk_users, email, first_name, last_name, status, hash_diff
      FROM sat_users
      ORDER BY load_dt DESC
      LIMIT 5;"

echo -e "\n✅ End-to-End тестирование завершено!"
