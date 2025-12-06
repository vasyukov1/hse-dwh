#!/bin/bash
set -e

echo "=== Starting DWH setup ==="


# Create .env if it doesn't exist
if [ ! -f .env ]; then
    echo "Creating .env from .env.example..."
    if [ -f .env.example ]; then
        cp .env.example .env
        echo ".env created successfully"
    else
        echo "ERROR: .env.example not found!"
        echo "Please create .env file manually"
        exit 1
    fi
fi

# Load environment variables
source .env 2>/dev/null || echo "WARNING: .env not found, using defaults"


# Clear data
echo "Clearing data"
rm -rf ./postgres-master-data/* 2>/dev/null || true
rm -rf ./postgres-replica-data/* 2>/dev/null || true
docker compose down -v 2>/dev/null || true


# Start master
echo "Starting postgres-master node..."
docker compose up -d postgres-master

# Wait for master to be ready
echo "Waiting for master to start..."
for i in {1..30}; do
    if docker exec postgres-master pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
        echo "Master is ready!"
        break
    fi
    sleep 2
    if [ $i -eq 30 ]; then
        echo "ERROR: Master failed to start within 60 seconds"
        exit 1
    fi
done


# Prepare replica config
echo "Prepare replica config..."
docker exec -it postgres-master sh /etc/postgresql/init-script/init.sh

# Restart master
echo "Restart master node"
docker compose restart postgres-master
sleep 5


# Start replica
echo "Starting replica node..."
docker compose up -d postgres-replica

# Wait for replica to be ready
echo "Waiting for replica to start..."
for i in {1..30}; do
    if docker exec postgres-replica pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
        echo "Replica is ready!"
        break
    fi
    sleep 2
    if [ $i -eq 30 ]; then
        echo "ERROR: Replica failed to start within 60 seconds"
        exit 1
    fi
done


echo "Connection strings:"
echo "  Master:      postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_MASTER_PORT/$POSTGRES_DB"
echo "  Replica:     postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@localhost:$POSTGRES_REPLICA_PORT/$POSTGRES_DB"
echo ""
echo "=== Setup completed successfully! ==="
