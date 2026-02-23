-- =========================================
-- Auto-generated Data Vault 2.0 DDL Script
-- =========================================
CREATE SCHEMA IF NOT EXISTS dwh_detailed;

-- ================= HUB & SAT: USERS =================
CREATE TABLE IF NOT EXISTS dwh_detailed.hub_users (
    hk_users VARCHAR(32) PRIMARY KEY,
    user_external_id uuid NOT NULL,
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'user_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.sat_users (
    hk_users VARCHAR(32) REFERENCES dwh_detailed.hub_users(hk_users),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    email varchar,
    first_name varchar,
    last_name varchar,
    phone varchar,
    date_of_birth date,
    registration_date timestamp,
    status varchar,
    effective_from timestamp,
    effective_to timestamp,
    is_current boolean,
    created_at timestamp,
    updated_at timestamp,
    created_by varchar,
    updated_by varchar,
    record_source VARCHAR(100) NOT NULL DEFAULT 'user_service',
    PRIMARY KEY (hk_users, load_dt)
);

-- ================= HUB & SAT: USER_ADDRESSES =================
CREATE TABLE IF NOT EXISTS dwh_detailed.hub_user_addresses (
    hk_user_addresses VARCHAR(32) PRIMARY KEY,
    address_external_id uuid NOT NULL,
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'user_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.sat_user_addresses (
    hk_user_addresses VARCHAR(32) REFERENCES dwh_detailed.hub_user_addresses(hk_user_addresses),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    address_type varchar,
    country varchar,
    region varchar,
    city varchar,
    street_address varchar,
    postal_code varchar,
    apartment varchar,
    is_default boolean,
    effective_from timestamp,
    effective_to timestamp,
    is_current boolean,
    created_at timestamp,
    updated_at timestamp,
    created_by varchar,
    updated_by varchar,
    record_source VARCHAR(100) NOT NULL DEFAULT 'user_service',
    PRIMARY KEY (hk_user_addresses, load_dt)
);

CREATE TABLE IF NOT EXISTS dwh_detailed.lnk_user_addresses_users (
    hk_lnk_user_addresses_users VARCHAR(32) PRIMARY KEY,
    hk_user_addresses VARCHAR(32) REFERENCES dwh_detailed.hub_user_addresses(hk_user_addresses),
    hk_users VARCHAR(32) REFERENCES dwh_detailed.hub_users(hk_users),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'user_service'
);

-- ================= SAT (History): USER_STATUS_HISTORY =================
CREATE TABLE IF NOT EXISTS dwh_detailed.sat_user_status_history (
    hk_users VARCHAR(32) REFERENCES dwh_detailed.hub_users(hk_users),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    old_status varchar,
    new_status varchar,
    change_reason varchar,
    changed_at timestamp,
    changed_by varchar,
    session_id varchar,
    ip_address inet,
    user_agent text,
    record_source VARCHAR(100) NOT NULL DEFAULT 'user_service',
    PRIMARY KEY (hk_users, load_dt)
);

-- ================= HUB & SAT: PRODUCTS =================
CREATE TABLE IF NOT EXISTS dwh_detailed.hub_products (
    hk_products VARCHAR(32) PRIMARY KEY,
    product_sku varchar NOT NULL,
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.sat_products (
    hk_products VARCHAR(32) REFERENCES dwh_detailed.hub_products(hk_products),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    product_name varchar,
    category varchar,
    brand varchar,
    price decimal,
    currency varchar,
    weight_grams integer,
    dimensions_length_cm decimal,
    dimensions_width_cm decimal,
    dimensions_height_cm decimal,
    is_active boolean,
    effective_from timestamp,
    effective_to timestamp,
    is_current boolean,
    created_at timestamp,
    updated_at timestamp,
    created_by varchar,
    updated_by varchar,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service',
    PRIMARY KEY (hk_products, load_dt)
);

-- ================= HUB & SAT: ORDERS =================
CREATE TABLE IF NOT EXISTS dwh_detailed.hub_orders (
    hk_orders VARCHAR(32) PRIMARY KEY,
    order_external_id uuid NOT NULL,
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.sat_orders (
    hk_orders VARCHAR(32) REFERENCES dwh_detailed.hub_orders(hk_orders),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    order_number varchar,
    order_date timestamp,
    status varchar,
    subtotal decimal,
    tax_amount decimal,
    shipping_cost decimal,
    discount_amount decimal,
    total_amount decimal,
    currency varchar,
    delivery_type varchar,
    expected_delivery_date date,
    actual_delivery_date date,
    payment_method varchar,
    payment_status varchar,
    effective_from timestamp,
    effective_to timestamp,
    is_current boolean,
    created_at timestamp,
    updated_at timestamp,
    created_by varchar,
    updated_by varchar,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service',
    PRIMARY KEY (hk_orders, load_dt)
);

CREATE TABLE IF NOT EXISTS dwh_detailed.lnk_orders_users (
    hk_lnk_orders_users VARCHAR(32) PRIMARY KEY,
    hk_orders VARCHAR(32) REFERENCES dwh_detailed.hub_orders(hk_orders),
    hk_users VARCHAR(32) REFERENCES dwh_detailed.hub_users(hk_users),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.lnk_orders_user_addresses (
    hk_lnk_orders_user_addresses VARCHAR(32) PRIMARY KEY,
    hk_orders VARCHAR(32) REFERENCES dwh_detailed.hub_orders(hk_orders),
    hk_user_addresses VARCHAR(32) REFERENCES dwh_detailed.hub_user_addresses(hk_user_addresses),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service'
);

-- ================= LINK & SAT: ORDER_ITEMS =================
CREATE TABLE IF NOT EXISTS dwh_detailed.lnk_order_items (
    hk_lnk_order_items VARCHAR(32) PRIMARY KEY,
    hk_orders VARCHAR(32) REFERENCES dwh_detailed.hub_orders(hk_orders),
    hk_products VARCHAR(32) REFERENCES dwh_detailed.hub_products(hk_products),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.sat_order_items (
    hk_lnk_order_items VARCHAR(32) REFERENCES dwh_detailed.lnk_order_items(hk_lnk_order_items),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    quantity integer,
    unit_price decimal,
    total_price decimal,
    product_name_snapshot varchar,
    product_category_snapshot varchar,
    product_brand_snapshot varchar,
    created_at timestamp,
    updated_at timestamp,
    created_by varchar,
    updated_by varchar,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service',
    PRIMARY KEY (hk_lnk_order_items, load_dt)
);

-- ================= SAT (History): ORDER_STATUS_HISTORY =================
CREATE TABLE IF NOT EXISTS dwh_detailed.sat_order_status_history (
    hk_orders VARCHAR(32) REFERENCES dwh_detailed.hub_orders(hk_orders),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    old_status varchar,
    new_status varchar,
    change_reason varchar,
    changed_at timestamp,
    changed_by varchar,
    session_id varchar,
    ip_address inet,
    notes text,
    record_source VARCHAR(100) NOT NULL DEFAULT 'order_service',
    PRIMARY KEY (hk_orders, load_dt)
);

-- ================= HUB & SAT: WAREHOUSES =================
CREATE TABLE IF NOT EXISTS dwh_detailed.hub_warehouses (
    hk_warehouses VARCHAR(32) PRIMARY KEY,
    warehouse_code varchar NOT NULL,
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.sat_warehouses (
    hk_warehouses VARCHAR(32) REFERENCES dwh_detailed.hub_warehouses(hk_warehouses),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    warehouse_name varchar,
    warehouse_type varchar,
    country varchar,
    region varchar,
    city varchar,
    street_address varchar,
    postal_code varchar,
    is_active boolean,
    max_capacity_cubic_meters decimal,
    operating_hours varchar,
    contact_phone varchar,
    manager_name varchar,
    effective_from timestamp,
    effective_to timestamp,
    is_current boolean,
    created_at timestamp,
    updated_at timestamp,
    created_by varchar,
    updated_by varchar,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service',
    PRIMARY KEY (hk_warehouses, load_dt)
);

-- ================= HUB & SAT: PICKUP_POINTS =================
CREATE TABLE IF NOT EXISTS dwh_detailed.hub_pickup_points (
    hk_pickup_points VARCHAR(32) PRIMARY KEY,
    pickup_point_code varchar NOT NULL,
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.sat_pickup_points (
    hk_pickup_points VARCHAR(32) REFERENCES dwh_detailed.hub_pickup_points(hk_pickup_points),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    pickup_point_name varchar,
    pickup_point_type varchar,
    country varchar,
    region varchar,
    city varchar,
    street_address varchar,
    postal_code varchar,
    is_active boolean,
    max_capacity_packages integer,
    operating_hours varchar,
    contact_phone varchar,
    partner_name varchar,
    effective_from timestamp,
    effective_to timestamp,
    is_current boolean,
    created_at timestamp,
    updated_at timestamp,
    created_by varchar,
    updated_by varchar,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service',
    PRIMARY KEY (hk_pickup_points, load_dt)
);

-- ================= HUB & SAT: SHIPMENTS =================
CREATE TABLE IF NOT EXISTS dwh_detailed.hub_shipments (
    hk_shipments VARCHAR(32) PRIMARY KEY,
    shipment_external_id uuid NOT NULL,
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.sat_shipments (
    hk_shipments VARCHAR(32) REFERENCES dwh_detailed.hub_shipments(hk_shipments),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    tracking_number varchar,
    status varchar,
    weight_grams integer,
    volume_cubic_cm integer,
    package_count integer,
    destination_type varchar,
    created_date timestamp,
    dispatched_date timestamp,
    estimated_delivery_date timestamp,
    actual_delivery_date timestamp,
    delivery_notes text,
    recipient_name varchar,
    delivery_signature varchar,
    effective_from timestamp,
    effective_to timestamp,
    is_current boolean,
    created_at timestamp,
    updated_at timestamp,
    created_by varchar,
    updated_by varchar,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service',
    PRIMARY KEY (hk_shipments, load_dt)
);

CREATE TABLE IF NOT EXISTS dwh_detailed.lnk_shipments_orders (
    hk_lnk_shipments_orders VARCHAR(32) PRIMARY KEY,
    hk_shipments VARCHAR(32) REFERENCES dwh_detailed.hub_shipments(hk_shipments),
    hk_orders VARCHAR(32) REFERENCES dwh_detailed.hub_orders(hk_orders),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.lnk_shipments_warehouses (
    hk_lnk_shipments_warehouses VARCHAR(32) PRIMARY KEY,
    hk_shipments VARCHAR(32) REFERENCES dwh_detailed.hub_shipments(hk_shipments),
    hk_warehouses VARCHAR(32) REFERENCES dwh_detailed.hub_warehouses(hk_warehouses),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.lnk_shipments_pickup_points (
    hk_lnk_shipments_pickup_points VARCHAR(32) PRIMARY KEY,
    hk_shipments VARCHAR(32) REFERENCES dwh_detailed.hub_shipments(hk_shipments),
    hk_pickup_points VARCHAR(32) REFERENCES dwh_detailed.hub_pickup_points(hk_pickup_points),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
);

CREATE TABLE IF NOT EXISTS dwh_detailed.lnk_shipments_user_addresses (
    hk_lnk_shipments_user_addresses VARCHAR(32) PRIMARY KEY,
    hk_shipments VARCHAR(32) REFERENCES dwh_detailed.hub_shipments(hk_shipments),
    hk_user_addresses VARCHAR(32) REFERENCES dwh_detailed.hub_user_addresses(hk_user_addresses),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service'
);

-- ================= SAT (History): SHIPMENT_MOVEMENTS =================
CREATE TABLE IF NOT EXISTS dwh_detailed.sat_shipment_movements (
    hk_shipments VARCHAR(32) REFERENCES dwh_detailed.hub_shipments(hk_shipments),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    movement_type varchar,
    location_type varchar,
    location_code varchar,
    movement_datetime timestamp,
    operator_name varchar,
    notes text,
    latitude decimal,
    longitude decimal,
    created_at timestamp,
    created_by varchar,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service',
    PRIMARY KEY (hk_shipments, load_dt)
);

-- ================= SAT (History): SHIPMENT_STATUS_HISTORY =================
CREATE TABLE IF NOT EXISTS dwh_detailed.sat_shipment_status_history (
    hk_shipments VARCHAR(32) REFERENCES dwh_detailed.hub_shipments(hk_shipments),
    load_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_diff VARCHAR(128) NOT NULL,
    old_status varchar,
    new_status varchar,
    change_reason varchar,
    changed_at timestamp,
    changed_by varchar,
    location_type varchar,
    location_code varchar,
    notes text,
    customer_notified boolean,
    record_source VARCHAR(100) NOT NULL DEFAULT 'logistics_service',
    PRIMARY KEY (hk_shipments, load_dt)
);
