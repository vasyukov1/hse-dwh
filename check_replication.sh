#!/bin/bash
set -e

MASTER_CONTAINER=postgres-master
REPLICA_CONTAINER=postgres-replica

MASTER_USER=postgres
REPLICA_USER=postgres

DB=postgres

echo "=== Checking MASTER readiness ==="
docker exec -it $MASTER_CONTAINER pg_isready -U $MASTER_USER || { echo "Master is NOT ready!"; exit 1; }
echo "Master is ready!"

echo
echo "=== Checking REPLICA readiness ==="
docker exec -it $REPLICA_CONTAINER pg_isready -U $REPLICA_USER || { echo "Replica is NOT ready!"; exit 1; }
echo "Replica is ready!"

echo
echo "=== Checking that replica is connected to master ==="
docker exec -it $MASTER_CONTAINER psql -U $MASTER_USER -d $DB -c "
    SELECT pid, client_addr, state, sync_state
    FROM pg_stat_replication;
"

echo
echo "=== Checking that pg_stat_replication returns at least one replica ==="
REPLICA_COUNT=$(docker exec $MASTER_CONTAINER psql -U $MASTER_USER -t -c "SELECT count(*) FROM pg_stat_replication;")
if [[ $REPLICA_COUNT -eq 0 ]]; then
    echo "ERROR: Replica is NOT connected to master!"
    exit 1
fi
echo "Replica is connected!"

echo
echo "=== Checking replica recovery status (should be in standby) ==="
docker exec -it $REPLICA_CONTAINER psql -U $REPLICA_USER -d $DB -c "
    SELECT pg_is_in_recovery();
"

IS_RECOVERY=$(docker exec $REPLICA_CONTAINER psql -U $REPLICA_USER -t -c "SELECT pg_is_in_recovery();")
if [[ $IS_RECOVERY != " t" ]]; then
    echo "ERROR: Replica is NOT in recovery mode! (so it's NOT a replica)"
    exit 1
fi
echo "Replica is in standby mode!"

echo
echo "=== Checking WAL replication lag ==="
docker exec -it $MASTER_CONTAINER psql -U $MASTER_USER -d $DB -c "
    SELECT
        pid,
        pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replication_lag
    FROM pg_stat_replication;
"

echo
echo "=== Testing actual data replication ==="
TEST_TABLE=test_replication_$(date +%s)

echo "Creating table on MASTER: $TEST_TABLE"
docker exec -it $MASTER_CONTAINER psql -U $MASTER_USER -d $DB -c "
    CREATE TABLE $TEST_TABLE(id INT);
    INSERT INTO $TEST_TABLE VALUES(1);
"

sleep 2

echo "Checking table on REPLICA"
docker exec -it $REPLICA_CONTAINER psql -U $REPLICA_USER -d $DB -c "
    SELECT * FROM $TEST_TABLE;
"

ROW_COUNT=$(docker exec $REPLICA_CONTAINER psql -U $REPLICA_USER -t -c "SELECT count(*) FROM $TEST_TABLE;")
if [[ $ROW_COUNT -eq 1 ]]; then
    echo "Real-time replication works!"
else
    echo "ERROR: Data did NOT replicate!"
    exit 1
fi

echo
echo "=== All replication checks passed SUCCESSFULLY! ==="
