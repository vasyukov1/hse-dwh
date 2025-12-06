# backup master
pg_basebackup -D /var/lib/postgresql/postgres-replica-data \
    -S replication_slot_1 \
    -X stream \
    -P \
    -U replicator \
    -Fp \
    -R
