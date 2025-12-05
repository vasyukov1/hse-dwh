# HSE Data Warehouse

Implementation of a Data Warehouse for a large marketplace with three microservice databases.

Author: Alexander Vasyukov.

## Overview

This project sets up a foundational DWH environment with PostgreSQL, including logical separation of three microservices:
- **user_service_db** - User information
- **order_service_db** - Order information  
- **logistics_service_db** - Shipment and logistics information

All databases reside on a single PostgreSQL instance with schema separation.

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

## Completed tasks
✅ **Step 1**: Set up PostgreSQL instance in Docker Compose.  
✅ **Step 2**: Automated database initialization.  
✅ **Step 3**: Schema migration and tables creation.  
✅ **Step 4**: Health monitoring setup.  

---

## Project Structure
```
hse-dwh/
├── migrations/ 
│   ├── 000_create_databases.sql
│   ├── 001_user_service_db.sql
│   ├── 002_order_service_db.sql
│   └── 003_logistics_service_db.sql
├── .env.example
├── .gitignore
├── docker-compose.yml
└── README.md
```

---

## How to Run

0. **Copy environment variables**:
```bash
cp .env.example .env
```

1. **Start the PostgreSQL instance:**
```bash
docker compose up
```
