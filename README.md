# HSE Data Warehouse

Implementation of a Data Warehouse for a large marketplace with three microservice databases using Data Vault 2.0 architecture and StarRocks MPP.

Author: Alexander Vasyukov.

## Overview

This project sets up a complete DWH environment including:
- **user_service_db** — User information and addresses
- **order_service_db** — Order and product information
- **logistics_service_db** — Shipment and logistics information

All databases reside on a single PostgreSQL master with streaming replication to a replica.
CDC is handled by Debezium → Kafka → DMP (Python) → StarRocks MPP (Data Vault 2.0).
Presentation layer is built via Apache Airflow DAGs and visualised in Metabase.

For the mart `dm_purchase_analytics`, the course clarification is:
- `supplier_id` and `supplier_name` are derived from product `brand`
- in this homework, `supplier = brand`

This mapping is implemented both in the StarRocks-based build and in the PostgreSQL fallback path inside [`airflow/dags/dwh_refresh.py`](/Users/alexvasyukov/Documents/GitHub/hse-dwh/airflow/dags/dwh_refresh.py).

---

## Quick Start

```bash
git clone https://github.com/vasyukov1/hse-dwh
cd hse-dwh

chmod +x docker-init.sh
./docker-init.sh
```

This single command:
1. Creates `.env` from `.env.example`
2. Generates the StarRocks Data Vault DDL from YAML
3. Starts PostgreSQL master + replica
4. Applies all schema migrations and creates Debezium publications
5. Starts StarRocks MPP and initialises both `dwh_detailed` and `presentation` schemas
6. Starts Kafka, Debezium Connect, and registers 3 CDC connectors
7. Starts the DMP service (Kafka → StarRocks loader)
8. Initialises and starts Apache Airflow (scheduler + webserver)
9. Starts Metabase BI

---

## Loading Test Data

```bash
chmod +x load_test_data.sh
./load_test_data.sh
```

The script loads all 12 CSV files in the correct FK-dependency order:

| Database | Table | File |
|---|---|---|
| user_service_db | users | `user_service_users.csv` |
| user_service_db | user_addresses | `user_service_user_addresses.csv` |
| user_service_db | user_status_history | `user_service_user_status_history.csv` |
| order_service_db | products | `order_service_products.csv` |
| order_service_db | orders | `order_service_orders.csv` |
| order_service_db | order_items | `order_service_order_items.csv` |
| order_service_db | order_status_history | `order_service_order_status_history.csv` |
| logistics_service_db | warehouses | `logistics_service_warehouses.csv` |
| logistics_service_db | pickup_points | `logistics_service_pickup_points.csv` |
| logistics_service_db | shipments | `logistics_service_shipments.csv` |
| logistics_service_db | shipment_movements | `logistics_service_shipment_movements.csv` |
| logistics_service_db | shipment_status_history | `logistics_service_shipment_status_history.csv` |

After loading, the script waits until the CDC pipeline catches up or until the timeout is reached, then prints row counts in both PostgreSQL and StarRocks. If the detailed layer is still catching up, the presentation DAGs can still be run because they fall back to PostgreSQL source tables.

---

## Triggering Airflow DAGs

After data is loaded, run the presentation-layer DAGs on business dates that exist in the source data:

```bash
chmod +x reinit_and_trigger.sh
./reinit_and_trigger.sh

docker exec airflow-scheduler airflow dags test dm_purchase_analytics 2025-10-08
docker exec airflow-scheduler airflow dags test dm_warehouse_delivery 2025-10-09
```

Or via the Airflow UI at **http://localhost:8080** (admin / admin).

`reinit_and_trigger.sh` now:
1. recreates `presentation` tables
2. waits for `dwh_detailed` to catch up for up to `WAIT_FOR_DWH_SEC` seconds
3. runs both marts on real business dates from the loaded CSVs
4. if `dwh_detailed` is still behind, the DAGs automatically fall back to source PostgreSQL

This matters for local verification because `dm_purchase_analytics` can contain many aggregated rows, and a too-early run previously looked like a hang even though the DAG was still inserting data.

## Recommended Run Order

For the homework demo, use this exact order:

```bash
./docker-init.sh
./load_test_data.sh
./reinit_and_trigger.sh
./tests/e2e/check_presentation_layer.sh
```

Expected result:
- `presentation.dm_purchase_analytics` is filled
- `presentation.dm_warehouse_delivery` is filled
- both tables are visible from Metabase after schema sync

If `dm_warehouse_delivery` looks empty in Metabase but has rows in StarRocks, run **Admin → Databases → StarRocks DWH → Sync database schema now** in Metabase.

---

## Connection Strings

| Service | Connection |
|---|---|
| PostgreSQL Master | `postgresql://postgres:postgres@localhost:5432/postgres` |
| PostgreSQL Replica | `postgresql://postgres:postgres@localhost:5433/postgres` |
| user_service_db | `postgresql://postgres:postgres@localhost:5432/user_service_db` |
| order_service_db | `postgresql://postgres:postgres@localhost:5432/order_service_db` |
| logistics_service_db | `postgresql://postgres:postgres@localhost:5432/logistics_service_db` |
| StarRocks SQL | `mysql -h 127.0.0.1 -P 9030 -u root -D presentation` |
| Airflow | http://localhost:8080 (admin / admin) |
| Metabase | http://localhost:3000 |
| Debezium | http://localhost:8083 |

---

## Architecture

```
PostgreSQL Master ──► Debezium CDC ──► Kafka ──► DMP Service ──► StarRocks MPP
       │                                                               │
       ▼                                                               ▼
PostgreSQL Replica                                            dwh_detailed (DV 2.0)
                                                                       │
                                                              Airflow DAGs
                                                                       │
                                                            presentation (CDM)
                                                                       │
                                                                  Metabase
```

### Source Microservices
Three PostgreSQL databases on a single instance, replicated to an async replica.
Schema migrations live in `migrations/`.

### CDC Layer
Debezium PostgreSQL connector streams WAL changes → Kafka topics:
- `user_service.public.*`
- `order_service.public.*`
- `logistics_service.public.*`

### DWH Layer — Data Vault 2.0 (StarRocks `dwh_detailed`)
Generated automatically from `dwh/source_schema.yaml` by `dwh/generate_ddl.py`.

**Hubs:** `hub_users`, `hub_user_addresses`, `hub_products`, `hub_orders`, `hub_warehouses`, `hub_pickup_points`, `hub_shipments`

**Links:** `lnk_user_addresses_users`, `lnk_orders_users`, `lnk_orders_user_addresses`, `lnk_order_items`, `lnk_shipments_orders`, `lnk_shipments_warehouses`, `lnk_shipments_pickup_points`, `lnk_shipments_user_addresses`

**Satellites:** `sat_users`, `sat_user_addresses`, `sat_user_status_history`, `sat_products`, `sat_orders`, `sat_order_status_history`, `sat_order_items`, `sat_warehouses`, `sat_pickup_points`, `sat_shipments`, `sat_shipment_movements`, `sat_shipment_status_history`

### Presentation Layer — CDM (StarRocks `presentation`)
Built by Airflow DAGs from the DV 2.0 layer. If the detailed layer is still catching up, the DAGs automatically fall back to the PostgreSQL source tables on the replica, which is allowed by the HW3 statement and makes local verification deterministic.

| Mart | Strategy | Schedule |
|---|---|---|
| `dm_purchase_analytics` | Full refresh (TRUNCATE + INSERT) | Daily 06:00 UTC |
| `dm_warehouse_delivery` | Incremental (DELETE + INSERT for yesterday) | Daily 07:00 UTC |

Semantics:
- `dm_purchase_analytics`: purchase analytics by day and product, where supplier is represented by product brand
- `dm_warehouse_delivery`: warehouse shipment analytics by shipment date

### BI — Metabase
Connect as MySQL: `host=starrocks, port=9030, user=root, db=presentation`.

See `docs/metabase_setup.md` for step-by-step dashboard creation guide.

## Dashboards And Screencast

The homework requires not only built dashboards, but also a short screencast showing that they work.

What must be prepared before recording:
- run `./docker-init.sh`
- load the CSVs with `./load_test_data.sh`
- rebuild and fill marts with `./reinit_and_trigger.sh`
- open Metabase and connect it to StarRocks as MySQL with `host=starrocks`, `port=9030`, `db=presentation`
- ensure both tables `dm_purchase_analytics` and `dm_warehouse_delivery` are visible in Metabase
- create two dashboards: purchases and warehouse delivery

What to record:
- architecture briefly: PostgreSQL → Debezium/Kafka/DMP → StarRocks → Airflow → Metabase
- that both marts exist and contain data
- dashboard 1 for purchases
- dashboard 2 for warehouse delivery
- a few interactions: open charts, filters, drill into numbers

[Screencast](docs/screencast)

---

## Data Vault 2.0 — Design Decisions

1. **Microservices fit** — each service becomes a distinct `record_source`; business keys cross service boundaries via Links
2. **Insert-only** — Hubs and Links never update, making CDC simple and idempotent
3. **Historicity** — Satellites capture every change via `hash_diff`; full audit trail
4. **Schema flexibility** — add new tables or services by editing `source_schema.yaml` and re-running `generate_ddl.py`

---

## StarRocks MPP — Design Decisions

- **UNIQUE KEY** tables for Hubs & Links (de-duplication on upsert)
- **DUPLICATE KEY** tables for Satellites (append-only history)
- MySQL-protocol compatibility → `pymysql` client, works in Metabase as a MySQL source
- Columnar storage + built-in compression for OLAP performance

---

## DDL Code Generator

```bash
python dwh/generate_ddl.py
# Output: dwh/ddl/001_starrocks_dwh_detailed.sql
```

Driven by `dwh/source_schema.yaml`. Re-run whenever the source schema changes.

---

## Testing

### Replication check
```bash
chmod +x check_replication.sh
./check_replication.sh
```

### End-to-end test (user service)
```bash
chmod +x tests/e2e/check_users.sh
./tests/e2e/check_users.sh
```

### Presentation layer check
```bash
chmod +x tests/e2e/check_presentation_layer.sh
./tests/e2e/check_presentation_layer.sh
```

---

## Cohort Analysis

```bash
# Create and run the cohort analysis view
docker exec -i postgres-master psql -U postgres -d order_service_db \
    < cohort_analysis/cohort_analysis.sql

docker exec -i postgres-master psql -U postgres -d order_service_db \
    < cohort_analysis/cohort_analysis_view.sql

# View results
docker exec postgres-master psql -U postgres -d order_service_db \
    -c "SELECT * FROM cohort_analysis_view;"
```

---

## Project Structure

```
hse-dwh/
├── airflow/
│   ├── dags/
│   │   └── dwh_refresh.py               # ← Both DAGs: dm_purchase_analytics + dm_warehouse_delivery
│   └── Dockerfile                       # Airflow + pymysql
├── cohort_analysis/
│   ├── cohort_analysis_view.sql
│   └── cohort_analysis.sql
├── debezium/
│   └── register-connectors.sh           # Idempotent connector registration
├── dmp/
│   ├── config.yaml                      # Universal DMP configuration (YAML-driven)
│   ├── Dockerfile
│   ├── main.py                          # Universal DMP service (Hub/Link/Satellite router)
│   └── requirements.txt
├── docs/
│   ├── data_vault.md                    # Data Vault structure docs
│   ├── metabase_setup.md                # Metabase dashboard setup guide
│   └── screencast_checklist.md          # What exactly to record for HW submission
├── dwh/
│   ├── ddl/
│   │   ├── 001_starrocks_dwh_detailed.sql   # Auto-generated DV 2.0 DDL
│   │   └── 002_starrocks_presentation.sql   # Presentation layer DDL (CDM)
│   ├── generate_ddl.py                  # DDL code generator
│   ├── requirements-generator.txt
│   └── source_schema.yaml               # Source schema config
├── init-script/                         # PostgreSQL replication setup
│   ├── bash/
│   │   ├── 0001-create-replica-user.sh
│   │   ├── 0002-backup-master.sh
│   │   └── 0003-init-slave.sh
│   ├── common-config/
│   │   ├── pg_hba.conf
│   │   └── postgresql.conf
│   ├── replica-config/
│   │   └── postgresql.auto.conf
│   └── init.sh
├── migrations/                          # Source DB schema migrations
│   ├── 000_create_databases.sql
│   ├── 001_user_service_db.sql
│   ├── 002_order_service_db.sql
│   └── 003_logistics_service_db.sql
├── test_data/                           # CSV test data (gitignored)
│   ├── user_service_users.csv
│   ├── user_service_user_addresses.csv
│   ├── user_service_user_status_history.csv
│   ├── order_service_products.csv
│   ├── order_service_orders.csv
│   ├── order_service_order_items.csv
│   ├── order_service_order_status_history.csv
│   ├── logistics_service_warehouses.csv
│   ├── logistics_service_pickup_points.csv
│   ├── logistics_service_shipments.csv
│   ├── logistics_service_shipment_movements.csv
│   └── logistics_service_shipment_status_history.csv
├── tests/
│   ├── data/
│   │   └── uesr_service_users.csv       # Small sample for e2e tests
│   └── e2e/
│       ├── check_users.sh
│       └── check_presentation_layer.sh
├── .env.example
├── .gitignore
├── check_replication.sh
├── docker-compose.yml
├── docker-init.sh                       # One-command full stack setup
├── load_test_data.sh                    # Load all 12 CSVs in correct FK order
├── reinit_and_trigger.sh                # Recreate presentation tables + run DAGs on detected business dates
├── README.md
├── dwh_detailed_diagram.mmd             # DWH ER diagram
└── src_database_diagram.mmd             # Source databases ER diagram
```

---

## Completed Tasks

✅ **Step 1**: PostgreSQL master + Docker Compose  
✅ **Step 2**: Automated DB initialisation  
✅ **Step 3**: Schema migrations and table creation  
✅ **Step 4**: Health monitoring  
✅ **Step 5**: PostgreSQL master → replica replication  
✅ **Step 6**: 6-month customer cohort analysis  
✅ **Step 7**: Data Vault 2.0 DDL for detailed DWH layer  
✅ **Step 8**: DWH ER diagram  
✅ **Step 9**: StarRocks MPP container  
✅ **Step 10**: Debezium CDC — 3 connectors registered  
✅ **Step 11**: Universal DMP service (Kafka → StarRocks)  
✅ **Step 12**: YAML-driven DDL generator  
✅ **Step 13**: StarRocks as MPP analytical database  
✅ **Step 14**: Universal DMP — single class + YAML config  
✅ **Step 15**: E2E tests for user service  
✅ **Step 16**: Apache Airflow in Docker Compose  
✅ **Step 17**: DAG — Витрина 1: `dm_purchase_analytics` (full refresh daily)  
✅ **Step 18**: DAG — Витрина 2: `dm_warehouse_delivery` (incremental daily)  
✅ **Step 19**: Metabase BI with 2 dashboards (purchases + warehouses)  
✅ **Step 20**: Presentation layer DDL (`002_starrocks_presentation.sql`)  
✅ **Step 21**: Clean unified test data loader (`load_test_data.sh`) for all 12 CSVs

---

## Resources

- [Data Vault 2.0 Official](https://www.data-vault.co.uk/)
- [StarRocks Documentation](https://docs.starrocks.io/)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [HSE DWH Course Materials](https://github.com/mgcrp/hse_se_dwh_course_2025)
