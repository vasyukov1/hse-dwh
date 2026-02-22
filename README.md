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

Implemented 6-month customer cohort analysis tracking retention rates, total revenue, and average revenue per customer from their first purchase month.

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

## DDL generator for detailed layer

The project has implementated a custom Python code generator for creating DDL scripts for the detailed DWH layer. The selected architecture of the detailed layer if Data Vault 2.0, as it perfectly handles historicity and microservices integration.

### The principle of operation

The generator (`dwh_generator/generate_ddl.py`) works on the principle of "Schema-Driven Development":
1. **Reading the source configuration**: The script accepts the input file `source_schema.yaml`, which contains metadata about the source tables (names, business key, attributes, foreign keys).
2. **Mapping in Data Vault 2.0**:
    - If an entity has a `business_key`, the generator automatically creates a table **HUB** (`hub_<entity>`) with a hash key (`hk_<entity>`), a business key, `load_dt` and `record_source`.
    - Non-key attributes of an entity are places in the **SATELLITE** table (`sat_<entity>`), which links to the Hub and contains the `hash_diff` field for tracking changes.
    - If the `references` block is specified in yaml (a link to another table), the genertor creates a **LINK** table (`link_<entity>_<target>`) linking the hash keys of the two Hubs.
3. **SQL Generation**: The script compiles all DDL commands and saves them to the migration directory (file `migrations/004_dwh_detailed_ddl.sql`), creating the schema `dwh_detailed`.

### Advantuges of the approach
- When adding new filed or tables in microservices, it is enough to simply update the yaml config. DDL for DWH will be updated automatically without manually writing the boilerplate code.
- Strict compliance with Data Vault naming standards (`hk_`, `hub_`, `sat_`, `link_`, `load_dt`).

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
✅ **Step 6**: Implemented Cohort Analysis.  

---

## Project Structure
```
hse-dwh/
├── cohort_analysis/
│   ├── cohort_analysis_view.sql            # Cohort analysis view
│   └── cohort_analysis.sql                 # Cohort analysis
├── debezium/
│   └── register-connectors.sh              # Idempotent connector registration for Debezium
├── dmp/
│   ├── venv/
│   ├── config.yaml                         # Config for DMP Service
│   ├── Dockerfile
│   ├── main.py                             # DMP Service
│   └── requirements.txt
├── docs/
│   └── data_vault.md                       # Data Vault docs
├── dwh/
│   └── ddl/                                # Data Vault 2.0
│       ├── 001_create_schema.sql           # Create DDL schema
│       ├── 002_create_hubs.sql             # Create hubs 
│       ├── 003_create_links.sql            # Create links
│       └── 004_create_satellites.sql       # Create satellite
├── dwh_generator/
│   ├── generate_ddl.py                     # DDL generator for detailed DWH layer 
│   ├── requirements-generator.txt
│   └── source_schema.yaml                  # Config for DDL
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
│   ├── 003_logistics_service_db.sql        # Logistics service tables
│   └── 004_dwh_detailed_ddl.sql            # DDL scripts for detailed DWH layer
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

Clone this repository:
```bash
git clone https://github.com/vasyukov1/hse-dwh
cd hse-dwh
```

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

5. **Register Debezium Connectors**:
    ```bash
    chmod +x debezium/register-connectors.sh
    ```

6. **Test for DWH**:
    ```bash
    chmod +x tests/e2e/check_users.sh
    chmod +x tests/e2e/check_logistics.sh

    ./tests/e2e/check_users.sh
    ./tests/e2e/check_logistics.sh
    ```

---

## Cohort Analysis

Run cohort analysis and view results:
```bash
docker exec -i postgres-master psql -U postgres -d order_service_db < cohort_analysis/cohort_analysis.sql
```

Run cohort analysis view:
```bash
docker exec -i postgres-master psql -U postgres -d order_service_db < cohort_analysis/cohort_analysis_view.sql
```

Watch cohort analysis results:
```bash
docker exec postgres-master psql -U postgres -d order_service_db -c "SELECT * FROM cohort_analysis_view;"
```
