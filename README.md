# HSE Data Warehouse

Implementation of a Data Warehouse for a large marketplace with three microservice databases.

Author: Alexander Vasyukov.

## Overview

This project sets up a foundational DWH environment with PostgreSQL, including logical separation of three microservices:
- **user_service_db** - User information
- **order_service_db** - Order information  
- **logistics_service_db** - Shipment and logistics information

All databases reside on a single PostgreSQL instance with schema separation.

The solution includes a master-replica setup with automatic initialization and replication configuration. The code is taken from [seminar](https://github.com/mgcrp/hse_se_dwh_course_2025/tree/master/week02/sem/demo2_automated_replication).

---

## Database Architecture

The solution implements a single PostgreSQL instance containing three logically separated databases:

1. **user_service_db**:
- `users`
- `user_addresses`
- `user_status_history`

2. **order_service_db**:
- `orders`
- `order_items`
- `order_status_history`
- `products`

3. **logistics_service_db**:
- `warehouses`
- `pickup_points`
- `shipments`
- `shipment_movements`
- `shipment_status_history`

Check existing of tables:
```bash
docker exec -it postgres-master psql -U <postgres_user> -d <db_name> -c "\dt"
```

---

## Connection Strings

- Master Node: `postgresql://postgres:postgres@localhost:5432/postgres`
- Replica Node: `postgresql://postgres:postgres@localhost:5433/postgres`
- User Service DB: `postgresql://postgres:postgres@localhost:5432/user_service_db`
- Order Service DB: `postgresql://postgres:postgres@localhost:5432/order_service_db`
- Logistics Service DB: `postgresql://postgres:postgres@localhost:5432/logistics_service_db`
---

## Completed tasks
✅ **Step 1**: Set up PostgreSQL instance in Docker Compose.  
✅ **Step 2**: Automated database initialization.  
✅ **Step 3**: Schema migration and tables creation.  
✅ **Step 4**: Health monitoring setup.  
✅ **Step 5**: PostgreSQL replication setup.  

---

## Project Structure
```
hse-dwh/
├── init-script/                            # Replication initialization scripts
│   ├── bash/
│   │   ├── 0001-create-replica-user.sh     # Create replication user
│   │   ├── 0002-backup-master.sh           # Backup master database
│   │   └── 0003-init-slave.sh              # Initialize replica from backup
│   ├── common-config/
│   │   ├── pg_hba.conf                     # Host-based authentication
│   │   └── postgrresql.conf                # Master configuration
│   ├── replica-config/
│   │   └── postgrresql.auto.conf           # Replica configuration
│   └── init.sh                             # Main initialization script
├── migrations/                             # Database schema migrations
│   ├── 000_create_databases.sql            # Create three databases
│   ├── 001_user_service_db.sql             # User service tables
│   ├── 002_order_service_db.sql            # Order service tables
│   └── 003_logistics_service_db.sql        # Logistics service tables
├── .env.example                            # Environment variables template
├── .gitignore                              # Git exclusion rules
├── check_replication.sh                    # Replication status verification
├── docker-compose.yml                      # Docker services definition
├── docker-init.sh                          # Complete initialization script
├── README.md                               # Documentation
└── src_database_diagram.mmd                # Database diagram source
```

---

## How to Run

### Quick Start

Make the initialization script executable and run it:
```bash
chmod +x docker-init.sh
./docker-init.sh
```

This script performs:
1. Create .env if it doesn't exist
2. Cleans up volumes
3. Stops and removes existing containers
4. Start master
5. Prepare replica config
6. Restart master
7. Start replica

### Manual Setup

1. **Environment Setup**:
    ```bash
    cp .env.example .env
    ```

2. **Start Services**:
    ```bash
    docker compose up -d

    chmod +x docker-init.sh
    ./docker-init.sh
    ```

3. **Check if containers are running**:
    ```bash
    docker compose ps
    ```

4. **Check replication status**:
    ```bash
    chmod +x check_replication.sh
    ./check_replication.sh
    ```
