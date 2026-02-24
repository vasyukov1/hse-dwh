-- =====================================================
-- Auto-generated Data Vault 2.0 DDL for StarRocks MPP
-- Source: source_schema.yaml
-- =====================================================

CREATE DATABASE IF NOT EXISTS dwh_detailed;
USE dwh_detailed;

-- ===== HUB: USERS =====
CREATE TABLE IF NOT EXISTS hub_users (
    hk_users     VARCHAR(32)   NOT NULL COMMENT 'MD5(user_external_id)',
    user_external_id          VARCHAR(36)     NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'user_service'
) UNIQUE KEY(hk_users)
COMMENT 'Hub: users'
DISTRIBUTED BY HASH(hk_users) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS sat_users (
    hk_users     VARCHAR(32)   NOT NULL,
    hash_diff     VARCHAR(128)  NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'user_service',
    email                          VARCHAR(500),
    first_name                     VARCHAR(500),
    last_name                      VARCHAR(500),
    phone                          VARCHAR(500),
    date_of_birth                  DATE,
    registration_date              DATETIME,
    status                         VARCHAR(500)
) UNIQUE KEY(hk_users, hash_diff)
COMMENT 'Satellite: users attributes'
DISTRIBUTED BY HASH(hk_users) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== HUB: USER_ADDRESSES =====
CREATE TABLE IF NOT EXISTS hub_user_addresses (
    hk_user_addresses     VARCHAR(32)   NOT NULL COMMENT 'MD5(address_external_id)',
    address_external_id          VARCHAR(36)     NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'user_service'
) UNIQUE KEY(hk_user_addresses)
COMMENT 'Hub: user_addresses'
DISTRIBUTED BY HASH(hk_user_addresses) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS sat_user_addresses (
    hk_user_addresses     VARCHAR(32)   NOT NULL,
    hash_diff     VARCHAR(128)  NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'user_service',
    address_type                   VARCHAR(500),
    country                        VARCHAR(500),
    region                         VARCHAR(500),
    city                           VARCHAR(500),
    street_address                 VARCHAR(500),
    postal_code                    VARCHAR(500),
    apartment                      VARCHAR(500),
    is_default                     BOOLEAN
) UNIQUE KEY(hk_user_addresses, hash_diff)
COMMENT 'Satellite: user_addresses attributes'
DISTRIBUTED BY HASH(hk_user_addresses) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS lnk_user_addresses_users (
    hk_lnk_user_addresses_users      VARCHAR(32)  NOT NULL,
    hk_user_addresses     VARCHAR(32)  NOT NULL,
    hk_users   VARCHAR(32)  NOT NULL,
    load_dt       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'user_service'
) UNIQUE KEY(hk_lnk_user_addresses_users)
COMMENT 'Link: user_addresses → users'
DISTRIBUTED BY HASH(hk_lnk_user_addresses_users) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== SAT: USER_STATUS_HISTORY =====
CREATE TABLE IF NOT EXISTS sat_user_status_history (
    hk_users   VARCHAR(32)   NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff     VARCHAR(128)  NOT NULL,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'user_service',
    old_status                     VARCHAR(500),
    new_status                     VARCHAR(500),
    change_reason                  VARCHAR(500),
    changed_at                     DATETIME,
    changed_by                     VARCHAR(500),
    session_id                     VARCHAR(500),
    ip_address                     VARCHAR(50),
    user_agent                     VARCHAR(65533)
) DUPLICATE KEY(hk_users, load_dt)
COMMENT 'Satellite: user_status_history'
DISTRIBUTED BY HASH(hk_users) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== HUB: PRODUCTS =====
CREATE TABLE IF NOT EXISTS hub_products (
    hk_products     VARCHAR(32)   NOT NULL COMMENT 'MD5(product_sku)',
    product_sku          VARCHAR(500)     NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'order_service'
) UNIQUE KEY(hk_products)
COMMENT 'Hub: products'
DISTRIBUTED BY HASH(hk_products) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS sat_products (
    hk_products     VARCHAR(32)   NOT NULL,
    hash_diff     VARCHAR(128)  NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'order_service',
    product_name                   VARCHAR(500),
    category                       VARCHAR(500),
    brand                          VARCHAR(500),
    price                          DECIMAL(18,2),
    currency                       VARCHAR(500),
    weight_grams                   INT,
    dimensions_length_cm           DECIMAL(18,2),
    dimensions_width_cm            DECIMAL(18,2),
    dimensions_height_cm           DECIMAL(18,2),
    is_active                      BOOLEAN
) UNIQUE KEY(hk_products, hash_diff)
COMMENT 'Satellite: products attributes'
DISTRIBUTED BY HASH(hk_products) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== HUB: ORDERS =====
CREATE TABLE IF NOT EXISTS hub_orders (
    hk_orders     VARCHAR(32)   NOT NULL COMMENT 'MD5(order_external_id)',
    order_external_id          VARCHAR(36)     NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'order_service'
) UNIQUE KEY(hk_orders)
COMMENT 'Hub: orders'
DISTRIBUTED BY HASH(hk_orders) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS sat_orders (
    hk_orders     VARCHAR(32)   NOT NULL,
    hash_diff     VARCHAR(128)  NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'order_service',
    order_number                   VARCHAR(500),
    order_date                     DATETIME,
    status                         VARCHAR(500),
    subtotal                       DECIMAL(18,2),
    tax_amount                     DECIMAL(18,2),
    shipping_cost                  DECIMAL(18,2),
    discount_amount                DECIMAL(18,2),
    total_amount                   DECIMAL(18,2),
    currency                       VARCHAR(500),
    delivery_type                  VARCHAR(500),
    expected_delivery_date         DATE,
    actual_delivery_date           DATE,
    payment_method                 VARCHAR(500),
    payment_status                 VARCHAR(500)
) UNIQUE KEY(hk_orders, hash_diff)
COMMENT 'Satellite: orders attributes'
DISTRIBUTED BY HASH(hk_orders) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS lnk_orders_users (
    hk_lnk_orders_users      VARCHAR(32)  NOT NULL,
    hk_orders     VARCHAR(32)  NOT NULL,
    hk_users   VARCHAR(32)  NOT NULL,
    load_dt       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service'
) UNIQUE KEY(hk_lnk_orders_users)
COMMENT 'Link: orders → users'
DISTRIBUTED BY HASH(hk_lnk_orders_users) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS lnk_orders_user_addresses (
    hk_lnk_orders_user_addresses      VARCHAR(32)  NOT NULL,
    hk_orders     VARCHAR(32)  NOT NULL,
    hk_user_addresses   VARCHAR(32)  NOT NULL,
    load_dt       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service'
) UNIQUE KEY(hk_lnk_orders_user_addresses)
COMMENT 'Link: orders → user_addresses'
DISTRIBUTED BY HASH(hk_lnk_orders_user_addresses) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== LINK+SAT: ORDER_ITEMS =====
CREATE TABLE IF NOT EXISTS lnk_order_items (
    hk_lnk_order_items      VARCHAR(32)  NOT NULL,
    hk_orders                   VARCHAR(32)  NOT NULL,
    hk_products                 VARCHAR(32)  NOT NULL,
    load_dt       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service'
) UNIQUE KEY(hk_lnk_order_items)
COMMENT 'Link: order_items'
DISTRIBUTED BY HASH(hk_lnk_order_items) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS sat_order_items (
    hk_lnk_order_items      VARCHAR(32)   NOT NULL,
    hash_diff     VARCHAR(128)  NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'order_service',
    quantity                       INT,
    unit_price                     DECIMAL(18,2),
    total_price                    DECIMAL(18,2),
    product_name_snapshot          VARCHAR(500),
    product_category_snapshot      VARCHAR(500),
    product_brand_snapshot         VARCHAR(500),
    created_at                     DATETIME,
    updated_at                     DATETIME,
    created_by                     VARCHAR(500),
    updated_by                     VARCHAR(500)
) UNIQUE KEY(hk_lnk_order_items, hash_diff)
COMMENT 'Satellite: order_items attributes (on Link)'
DISTRIBUTED BY HASH(hk_lnk_order_items) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== SAT: ORDER_STATUS_HISTORY =====
CREATE TABLE IF NOT EXISTS sat_order_status_history (
    hk_orders   VARCHAR(32)   NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff     VARCHAR(128)  NOT NULL,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'order_service',
    old_status                     VARCHAR(500),
    new_status                     VARCHAR(500),
    change_reason                  VARCHAR(500),
    changed_at                     DATETIME,
    changed_by                     VARCHAR(500),
    session_id                     VARCHAR(500),
    ip_address                     VARCHAR(50),
    notes                          VARCHAR(65533)
) DUPLICATE KEY(hk_orders, load_dt)
COMMENT 'Satellite: order_status_history'
DISTRIBUTED BY HASH(hk_orders) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== HUB: WAREHOUSES =====
CREATE TABLE IF NOT EXISTS hub_warehouses (
    hk_warehouses     VARCHAR(32)   NOT NULL COMMENT 'MD5(warehouse_code)',
    warehouse_code          VARCHAR(500)     NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'logistics_service'
) UNIQUE KEY(hk_warehouses)
COMMENT 'Hub: warehouses'
DISTRIBUTED BY HASH(hk_warehouses) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS sat_warehouses (
    hk_warehouses     VARCHAR(32)   NOT NULL,
    hash_diff     VARCHAR(128)  NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'logistics_service',
    warehouse_name                 VARCHAR(500),
    warehouse_type                 VARCHAR(500),
    country                        VARCHAR(500),
    region                         VARCHAR(500),
    city                           VARCHAR(500),
    street_address                 VARCHAR(500),
    postal_code                    VARCHAR(500),
    is_active                      BOOLEAN,
    max_capacity_cubic_meters      DECIMAL(18,2),
    operating_hours                VARCHAR(500),
    contact_phone                  VARCHAR(500),
    manager_name                   VARCHAR(500)
) UNIQUE KEY(hk_warehouses, hash_diff)
COMMENT 'Satellite: warehouses attributes'
DISTRIBUTED BY HASH(hk_warehouses) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== HUB: PICKUP_POINTS =====
CREATE TABLE IF NOT EXISTS hub_pickup_points (
    hk_pickup_points     VARCHAR(32)   NOT NULL COMMENT 'MD5(pickup_point_code)',
    pickup_point_code          VARCHAR(500)     NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'logistics_service'
) UNIQUE KEY(hk_pickup_points)
COMMENT 'Hub: pickup_points'
DISTRIBUTED BY HASH(hk_pickup_points) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS sat_pickup_points (
    hk_pickup_points     VARCHAR(32)   NOT NULL,
    hash_diff     VARCHAR(128)  NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'logistics_service',
    pickup_point_name              VARCHAR(500),
    pickup_point_type              VARCHAR(500),
    country                        VARCHAR(500),
    region                         VARCHAR(500),
    city                           VARCHAR(500),
    street_address                 VARCHAR(500),
    postal_code                    VARCHAR(500),
    is_active                      BOOLEAN,
    max_capacity_packages          INT,
    operating_hours                VARCHAR(500),
    contact_phone                  VARCHAR(500),
    partner_name                   VARCHAR(500)
) UNIQUE KEY(hk_pickup_points, hash_diff)
COMMENT 'Satellite: pickup_points attributes'
DISTRIBUTED BY HASH(hk_pickup_points) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== HUB: SHIPMENTS =====
CREATE TABLE IF NOT EXISTS hub_shipments (
    hk_shipments     VARCHAR(32)   NOT NULL COMMENT 'MD5(shipment_external_id)',
    shipment_external_id          VARCHAR(36)     NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'logistics_service'
) UNIQUE KEY(hk_shipments)
COMMENT 'Hub: shipments'
DISTRIBUTED BY HASH(hk_shipments) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS sat_shipments (
    hk_shipments     VARCHAR(32)   NOT NULL,
    hash_diff     VARCHAR(128)  NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'logistics_service',
    tracking_number                VARCHAR(500),
    status                         VARCHAR(500),
    weight_grams                   INT,
    volume_cubic_cm                INT,
    package_count                  INT,
    destination_type               VARCHAR(500),
    created_date                   DATETIME,
    dispatched_date                DATETIME,
    estimated_delivery_date        DATETIME,
    actual_delivery_date           DATETIME,
    delivery_notes                 VARCHAR(65533),
    recipient_name                 VARCHAR(500),
    delivery_signature             VARCHAR(500)
) UNIQUE KEY(hk_shipments, hash_diff)
COMMENT 'Satellite: shipments attributes'
DISTRIBUTED BY HASH(hk_shipments) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS lnk_shipments_orders (
    hk_lnk_shipments_orders      VARCHAR(32)  NOT NULL,
    hk_shipments     VARCHAR(32)  NOT NULL,
    hk_orders   VARCHAR(32)  NOT NULL,
    load_dt       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
) UNIQUE KEY(hk_lnk_shipments_orders)
COMMENT 'Link: shipments → orders'
DISTRIBUTED BY HASH(hk_lnk_shipments_orders) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS lnk_shipments_warehouses (
    hk_lnk_shipments_warehouses      VARCHAR(32)  NOT NULL,
    hk_shipments     VARCHAR(32)  NOT NULL,
    hk_warehouses   VARCHAR(32)  NOT NULL,
    load_dt       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
) UNIQUE KEY(hk_lnk_shipments_warehouses)
COMMENT 'Link: shipments → warehouses'
DISTRIBUTED BY HASH(hk_lnk_shipments_warehouses) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS lnk_shipments_pickup_points (
    hk_lnk_shipments_pickup_points      VARCHAR(32)  NOT NULL,
    hk_shipments     VARCHAR(32)  NOT NULL,
    hk_pickup_points   VARCHAR(32)  NOT NULL,
    load_dt       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
) UNIQUE KEY(hk_lnk_shipments_pickup_points)
COMMENT 'Link: shipments → pickup_points'
DISTRIBUTED BY HASH(hk_lnk_shipments_pickup_points) BUCKETS 4
PROPERTIES ("replication_num" = "1");

CREATE TABLE IF NOT EXISTS lnk_shipments_user_addresses (
    hk_lnk_shipments_user_addresses      VARCHAR(32)  NOT NULL,
    hk_shipments     VARCHAR(32)  NOT NULL,
    hk_user_addresses   VARCHAR(32)  NOT NULL,
    load_dt       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
) UNIQUE KEY(hk_lnk_shipments_user_addresses)
COMMENT 'Link: shipments → user_addresses'
DISTRIBUTED BY HASH(hk_lnk_shipments_user_addresses) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== SAT: SHIPMENT_MOVEMENTS =====
CREATE TABLE IF NOT EXISTS sat_shipment_movements (
    hk_shipments   VARCHAR(32)   NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff     VARCHAR(128)  NOT NULL,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'logistics_service',
    movement_type                  VARCHAR(500),
    location_type                  VARCHAR(500),
    location_code                  VARCHAR(500),
    movement_datetime              DATETIME,
    operator_name                  VARCHAR(500),
    notes                          VARCHAR(65533),
    latitude                       DECIMAL(18,2),
    longitude                      DECIMAL(18,2),
    created_at                     DATETIME,
    created_by                     VARCHAR(500)
) DUPLICATE KEY(hk_shipments, load_dt)
COMMENT 'Satellite: shipment_movements'
DISTRIBUTED BY HASH(hk_shipments) BUCKETS 4
PROPERTIES ("replication_num" = "1");

-- ===== SAT: SHIPMENT_STATUS_HISTORY =====
CREATE TABLE IF NOT EXISTS sat_shipment_status_history (
    hk_shipments   VARCHAR(32)   NOT NULL,
    load_dt       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff     VARCHAR(128)  NOT NULL,
    record_source VARCHAR(100)  NOT NULL DEFAULT 'logistics_service',
    old_status                     VARCHAR(500),
    new_status                     VARCHAR(500),
    change_reason                  VARCHAR(500),
    changed_at                     DATETIME,
    changed_by                     VARCHAR(500),
    location_type                  VARCHAR(500),
    location_code                  VARCHAR(500),
    notes                          VARCHAR(65533),
    customer_notified              BOOLEAN
) DUPLICATE KEY(hk_shipments, load_dt)
COMMENT 'Satellite: shipment_status_history'
DISTRIBUTED BY HASH(hk_shipments) BUCKETS 4
PROPERTIES ("replication_num" = "1");
