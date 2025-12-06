#!/bin/bash
set -e

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

# Clear data
echo "Clearing data"
rm -rf ./postgres-master-data/*
rm -rf ./postgres-replica-data/*
docker compose down

# Start master
docker compose up -d postgres-master
echo "Starting postgres-master node..."
sleep 10

# Prepare replica config
echo "Prepare replica config..."
docker exec -it postgres-master sh /etc/postgresql/init-script/init.sh

# Restart master
echo "Restart master node"
docker compose restart postgres-master
sleep 10

# Start replica
echo "Starting replica node..."
docker compose up -d postgres-replica
sleep 10

echo "Done"
