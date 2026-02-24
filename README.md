# HSE Data Warehouse

Implementation of a Data Warehouse for a large marketplace with three microservice databases using Data Vault 2.0 architecture and StarRocks MPP.

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

**Main Requirements:**
- **Architecture Selection & DDL**: Data Vault 2.0 architecture with full DDL
  - DDL file: [`dwh/ddl/001_starrocks_dwh_detailed.sql`](dwh/ddl/001_starrocks_dwh_detailed.sql)
  - ER Diagram: [`dwh_detailed_diagram.mmd`](dwh_detailed_diagram.mmd)
  - Architecture docs: [`docs/data_vault.md`](docs/data_vault.md)
 
- **Debezium Integration**: Full CDC setup with Kafka
  - Connector registration: [`debezium/register-connectors.sh`](debezium/register-connectors.sh)
  - 3 connectors: user_service, order_service, logistics_service
  
- **DMP Service**: Python service for data processing
  - Service code: [`dmp/main.py`](dmp/main.py)
  - Configuration: [`dmp/config.yaml`](dmp/config.yaml)

- **DDL Code Generator**: YAML-driven DDL generation
  - Generator: [`dwh/generate_ddl.py`](dwh/generate_ddl.py)
  - Config: [`dwh/source_schema.yaml`](dwh/source_schema.yaml)
  
- **MPP Database**: StarRocks instead of PostgreSQL
  - Auto-generated DDL optimized for MPP

---

## Architecture

This project implements a complete data warehouse solution with:
- **Source Systems**: 3 microservice databases (PostgreSQL)
- **CDC Layer**: Debezium + Kafka
- **DWH Layer**: StarRocks MPP with Data Vault 2.0
- **Orchestration**: Docker Compose

### Source Microservices:
1. **user_service_db** - User information and addresses
2. **order_service_db** - Orders, products, and order items  
3. **logistics_service_db** - Shipments, warehouses, and movements

Check existing of tables:
```bash
docker exec -it postgres-master psql -U <postgres_user> -d <db_name> -c "\dt"
```

---

## Data Vault 2.0

**Decision rationale:**

1. **Microservices Architecture Fit**: Data Vault 2.0 naturally handles data from multiple source systems with different business keys and relationships. Each microservice becomes a separate `record_source`.

2. **Historicity & Auditability**: 
   - **Hubs** store immutable business keys
   - **Satellites** track attribute changes with `load_dt` and `hash_diff`
   - **Links** capture evolving relationships between entities
   - Perfect for tracking order status changes, user profile updates, shipment movements

3. **Incremental Loading**: 
   - Insert-only pattern (no updates/deletes in Hubs/Links)
   - Efficient CDC processing from Debezium
   - Easy to parallelize across multiple entities

4. **Schema Flexibility**:
   - Easy to add new sources without restructuring
   - Satellites can be added/modified independently
   - Links support many-to-many relationships naturally

5. **Cross-Database References**: 
   - Orders reference users from another database
   - Shipments reference addresses and orders from other systems
   - Data Vault handles this through business keys and Links

---

## StarRocks MPP

**Decision rationale:**

1. **True MPP Architecture**: 
   - Distributed query execution across BE nodes
   - Scales horizontally for large datasets
   - Much faster than single-node PostgreSQL for OLAP

2. **Data Vault Optimization**:
   - Efficient JOIN performance (unlike ClickHouse)
   - Supports complex multi-table queries needed for Data Vault
   - UNIQUE KEY tables for Hubs/Links (de-duplication)
   - DUPLICATE KEY tables for Satellites (append-only)

3. **MySQL Protocol Compatibility**:
   - Easy integration with existing tools
   - Simple Python connectivity via `pymysql`
   - No need for specialized drivers

4. **Real-time Ingestion**:
   - Sub-second INSERT latency
   - Perfect for streaming CDC from Kafka
   - No need for batch processing

5. **Storage Efficiency**:
   - Columnar storage reduces disk usage
   - Built-in compression
   - Automatic data compaction

---

## DDL Code Generator

**Principle of operation:**

The generator (`dwh/generate_ddl.py`) implements **Schema-Driven Development** for Data Vault 2.0:

Running the generator:
```bash
python dwh/generate_ddl.py
# Output: dwh/ddl/001_starrocks_dwh_detailed.sql
```

---

## Universal DMP Class with YAML Configs

### Processing Flow:
1. **Kafka message arrives** → DMP identifies topic
2. **Load topic config** from YAML
3. **Route to appropriate method**:
   - `_process_hub()` → Create Hub record
   - `_process_link()` → Create Link record
   - `_process_satellite()` → Create Satellite record with hash_diff
4. **Insert to StarRocks** with proper hash keys


### Key Features:
- **No code changes** when adding new tables - just update YAML
- **Automatic hash key generation** - MD5(business_key)
- **Automatic hash_diff** - MD5(all attributes) for change detection
- **Type coercion** - handles timestamps, dates, integers automatically
- **Error handling** - logs warnings, continues processing

---


## Database Architecture

The solution implements three logically separated databases:

1. **user_service_db**:
   - `users` - User profiles with SCD Type 2
   - `user_addresses` - User addresses with versioning
   - `user_status_history` - Status change tracking

2. **order_service_db**:
   - `orders` - Order headers with SCD Type 2
   - `order_items` - Line items with product snapshots
   - `order_status_history` - Status change tracking
   - `products` - Product catalog with versioning

3. **logistics_service_db**:
   - `warehouses` - Warehouse information
   - `pickup_points` - Pickup point locations
   - `shipments` - Shipment tracking
   - `shipment_movements` - Movement history
   - `shipment_status_history` - Status changes

**Source ER Diagram**: [`src_database_diagram.mmd`](src_database_diagram.mmd)

---

### DWH Database (StarRocks MPP)

Data Vault 2.0 structure in `dwh_detailed` schema:

**Hubs:**
- `hub_users`, `hub_user_addresses`, `hub_products`, `hub_orders`
- `hub_warehouses`, `hub_pickup_points`, `hub_shipments`

**Links:**
- `lnk_user_addresses_users`, `lnk_orders_users`, `lnk_orders_user_addresses`
- `lnk_order_items`, `lnk_shipments_orders`, `lnk_shipments_warehouses`
- `lnk_shipments_pickup_points`, `lnk_shipments_user_addresses`

**Satellites:**
- Regular: `sat_users`, `sat_user_addresses`, `sat_products`, `sat_orders`, etc.
- History: `sat_user_status_history`, `sat_order_status_history`, `sat_shipment_movements`, etc.

**DWH ER Diagram**: [`dwh_detailed_diagram.mmd`](dwh_detailed_diagram.mmd)

Check existing tables:
```bash
docker exec -it postgres-master psql -U postgres -d user_service_db -c "\dt"
docker exec -it starrocks mysql -h 127.0.0.1 -P 9030 -u root -D dwh_detailed -e "SHOW TABLES;"
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
✅ **Step 6**: Implemented Cohort Analysis.  
✅ **Step 7**: DDL for detailed DWH layer.  
✅ **Step 8**: DWH ER Diagram.  
✅ **Step 9**: DWH instance initialized - StarRocks container  
✅ **Step 10**: Debezium connected - 3 connectors registered and working  
✅ **Step 11**: DMP service working  
✅ **Step 12**: DDL Generator  
✅ **Step 13**: MPP Database - StarRocks instead of PostgreSQL  
✅ **Step 14**: Universal DMP - Single class + YAML configs  
✅ **Step 15**: E2E Tests for user service

---

## Project Structure
```
hse-dwh/
├── cohort_analysis/
│   ├── cohort_analysis_view.sql            # Cohort analysis view
│   └── cohort_analysis.sql                 # Cohort analysis query
├── debezium/
│   └── register-connectors.sh              # Idempotent connector registration
├── dmp/
│   ├── config.yaml                         # Universal DMP configuration
│   ├── Dockerfile
│   ├── main.py                             # Universal DMP service
│   └── requirements.txt
├── docs/
│   ├── data_vault.md                       # Data Vault documentation
│   └── dwh_detailed_diagram.png            # DWH diagram
├── dwh/
│   ├── ddl/                                # Data Vault 2.0
│   │   └── 001_starrocks_dwh_detailed.sql  # Generated DDL for StarRocks
│   ├── generate_ddl.py                     # DDL code generator
│   ├── requirements-generator.txt
│   └── source_schema.yaml                  # Config for DDL
├── init-script/                            # Replication initialization
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
├── spark/  
│   └── Dockerfile                          # Dockerfile for Spark
├── tests/ 
│   ├── data/                               # Data for tests
│   │   └── user_sesrvice_users.csv         
│   └── e2e/
│       └── check_users.sh                  # E2E test for user service
├── .env.example                            # Environment variables template
├── .gitignore                              # Git exclusion rules
├── check_replication.sh                    # Replication status verification
├── docker-compose.yml                      # Full stack orchestration
├── docker-init.sh                          # Complete initialization script
├── README.md                               # Documentation
├── src_database_diagram.mmd                # Source databases ER diagram
└── dwh_detailed_diagram.mmd                # DWH ER diagram
```

---

## How to Run

Clone this repository:
```bash
git clone https://github.com/vasyukov1/hse-dwh
cd hse-dwh
```

### Quick Start

Clone the repository:
```bash
git clone https://github.com/vasyukov1/hse-dwh
cd hse-dwh
```

Run the initialization script:
```bash
chmod +x docker-init.sh
./docker-init.sh
```

This script performs:
1. Creates .env from .env.example
2. Generates Data Vault 2.0 DDL from YAML config
3. Cleans up old volumes
4. Starts PostgreSQL master
5. Creates service databases
6. Creates replication user and publications
7. Prepares replica configuration with pg_basebackup
8. Starts PostgreSQL replica
9. Starts StarRocks MPP and initializes DWH schema
10. Starts Kafka broker
11. Creates Debezium internal topics
12. Starts Debezium Connect
13. Registers CDC connectors
14. Starts DMP service

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

## Testing

### End-to-End Tests

The project includes automated tests to verify the entire pipeline:

**Test 1: User Service Pipeline**
```bash
chmod +x tests/e2e/check_users.sh
./tests/e2e/check_users.sh
```

This test:
1. Inserts test users into `postgres-master`
2. Verifies physical replication to `postgres-replica`
3. Checks Kafka topic for CDC events
4. Verifies Hub creation in StarRocks
5. Verifies Satellite creation with attributes

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

---

## Resources

- [Data Vault 2.0 Official](https://www.data-vault.co.uk/)
- [StarRocks Documentation](https://docs.starrocks.io/)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [HSE DWH Course Materials](https://github.com/mgcrp/hse_se_dwh_course_2025)

