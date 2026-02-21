-- =========================================
-- HUB: User
-- =========================================
CREATE TABLE IF NOT EXISTS hub_user (
    hub_user_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_external_id    UUID NOT NULL UNIQUE,
    load_date           TIMESTAMP NOT NULL DEFAULT now(),
    record_source       VARCHAR NOT NULL DEFAULT 'user_service'
);

CREATE INDEX IF NOT EXISTS idx_hub_user_external_id ON hub_user(user_external_id);
CREATE INDEX IF NOT EXISTS idx_hub_user_load_date   ON hub_user(load_date);


-- =========================================
-- HUB: Order
-- =========================================
CREATE TABLE IF NOT EXISTS hub_order (
    hub_order_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_external_id   UUID NOT NULL UNIQUE,
    load_date           TIMESTAMP NOT NULL DEFAULT now(),
    record_source       VARCHAR NOT NULL DEFAULT 'order_service'
);

CREATE INDEX IF NOT EXISTS idx_hub_order_external_id ON hub_order(order_external_id);
CREATE INDEX IF NOT EXISTS idx_hub_order_load_date   ON hub_order(load_date);


-- =========================================
-- HUB: Product
-- =========================================
CREATE TABLE IF NOT EXISTS hub_product (
    hub_product_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_external_id UUID NOT NULL UNIQUE,
    load_date           TIMESTAMP NOT NULL DEFAULT now(),
    record_source       VARCHAR NOT NULL DEFAULT 'order_service'
);

CREATE INDEX IF NOT EXISTS idx_hub_product_external_id ON hub_product(product_external_id);
CREATE INDEX IF NOT EXISTS idx_hub_product_load_date   ON hub_product(load_date);


-- =========================================
-- HUB: Warehouse
-- =========================================
CREATE TABLE IF NOT EXISTS hub_warehouse (
    hub_warehouse_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    warehouse_external_id   UUID NOT NULL UNIQUE,
    load_date               TIMESTAMP NOT NULL DEFAULT now(),
    record_source           VARCHAR NOT NULL DEFAULT 'logistics_service'
);

CREATE INDEX IF NOT EXISTS idx_hub_warehouse_external_id ON hub_warehouse(warehouse_external_id);
CREATE INDEX IF NOT EXISTS idx_hub_warehouse_load_date   ON hub_warehouse(load_date);


-- =========================================
-- HUB: Pickup Point
-- =========================================
CREATE TABLE IF NOT EXISTS hub_pickup_point (
    hub_pickup_point_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    pickup_point_external_id    UUID NOT NULL UNIQUE,
    load_date                   TIMESTAMP NOT NULL DEFAULT now(),
    record_source               VARCHAR NOT NULL DEFAULT 'logistics_service'
);

CREATE INDEX IF NOT EXISTS idx_hub_pickup_point_external_id 
    ON hub_pickup_point(pickup_point_external_id);

CREATE INDEX IF NOT EXISTS idx_hub_pickup_point_load_date 
    ON hub_pickup_point(load_date);


-- =========================================
-- HUB: Shipment
-- =========================================
CREATE TABLE IF NOT EXISTS hub_shipment (
    hub_shipment_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shipment_external_id   UUID NOT NULL UNIQUE,
    load_date              TIMESTAMP NOT NULL DEFAULT now(),
    record_source          VARCHAR NOT NULL DEFAULT 'logistics_service'
);

CREATE INDEX IF NOT EXISTS idx_hub_shipment_external_id ON hub_shipment(shipment_external_id);
CREATE INDEX IF NOT EXISTS idx_hub_shipment_load_date   ON hub_shipment(load_date);


-- =========================================
-- HUB: Address
-- =========================================
CREATE TABLE IF NOT EXISTS hub_address (
    hub_address_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    address_external_id   UUID NOT NULL UNIQUE,
    load_date             TIMESTAMP NOT NULL DEFAULT now(),
    record_source         VARCHAR NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_hub_address_external_id ON hub_address(address_external_id);
CREATE INDEX IF NOT EXISTS idx_hub_address_load_date   ON hub_address(load_date);
