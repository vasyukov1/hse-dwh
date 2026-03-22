-- =====================================================
-- Presentation Layer — StarRocks MPP
-- HW3: Витрина 1 (закупки) + Витрина 2 (склады)
-- =====================================================

CREATE DATABASE IF NOT EXISTS presentation;
USE presentation;

-- ─────────────────────────────────────────────────────
-- Витрина 1: dm_purchase_analytics
-- Аналитика закупок (полный рефреш 1 раз в день)
-- ─────────────────────────────────────────────────────
DROP TABLE IF EXISTS dm_purchase_analytics;

CREATE TABLE IF NOT EXISTS dm_purchase_analytics (
    purchase_date           DATE            NOT NULL,
    product_id              INT             NOT NULL,
    supplier_id             INT             NOT NULL,
    product_name            VARCHAR(500),
    category                VARCHAR(500),
    supplier_name           VARCHAR(500),
    purchase_qty            DECIMAL(18,2),
    total_purchase_amount   DECIMAL(18,2),
    avg_unit_price          DECIMAL(18,2),
    load_dt                 DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
) DUPLICATE KEY(purchase_date, product_id, supplier_id)
COMMENT 'Витрина 1: Аналитика закупок'
DISTRIBUTED BY HASH(purchase_date) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ─────────────────────────────────────────────────────
-- Витрина 2: dm_warehouse_delivery
-- Доставка по складам (инкремент за вчера)
-- ─────────────────────────────────────────────────────
DROP TABLE IF EXISTS dm_warehouse_delivery;

CREATE TABLE IF NOT EXISTS dm_warehouse_delivery (
    shipment_date           DATE            NOT NULL,
    warehouse_id            INT             NOT NULL,
    warehouse_name          VARCHAR(500),
    order_count             INT             NOT NULL,
    total_shipment_qty      DECIMAL(18,2),
    avg_processing_time_min DECIMAL(18,2),
    delayed_orders_count    INT             NOT NULL,
    unique_customers_count  INT             NOT NULL,
    load_dt                 DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
) UNIQUE KEY(shipment_date, warehouse_id)
COMMENT 'Витрина 2: Доставка по складам'
DISTRIBUTED BY HASH(warehouse_id) BUCKETS 4
PROPERTIES ("replication_num" = "1");
