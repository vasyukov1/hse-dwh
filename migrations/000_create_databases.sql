-- user_service_db
SELECT 'CREATE DATABASE user_service_db'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'user_service_db'
)\gexec

-- order_service_db
SELECT 'CREATE DATABASE order_service_db'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'order_service_db'
)\gexec

-- logistics_service_db
SELECT 'CREATE DATABASE logistics_service_db'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'logistics_service_db'
)\gexec
