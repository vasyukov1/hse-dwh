# HSE Data Warehouse

Implementation of a Data Warehouse for a large marketplace with three microservice databases.

Author: Alexander Vasyukov.

## Overview

This project sets up a foundational DWH environment with PostgreSQL, including logical separation of three microservices:
- **user_service_db** - User information
- **order_service_db** - Order information  
- **logistics_service_db** - Shipment and logistics information

All databases reside on a single PostgreSQL instance with schema separation.


## Homework 1

### Completed tasks
✅ **Step 1**: Set up PostgreSQL instance in Docker Compose


## Project Structure
```
hse-dwh/
├── .env.example
├── .gitignore
├── docker-compose.yml
└── README.md
```


## How to Run

0. **Copy environment variables**:
```bash
cp .env.example .env
```

1. **Start the PostgreSQL instance:**
```bash
docker compose up
```
