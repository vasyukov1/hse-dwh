-- =========================================
-- LINK: Order - User
-- =========================================
CREATE TABLE IF NOT EXISTS link_order_user (
    link_order_user_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hub_order_id        UUID NOT NULL,
    hub_user_id         UUID NOT NULL,
    load_date           TIMESTAMP NOT NULL DEFAULT now(),
    record_source       VARCHAR NOT NULL DEFAULT 'order_service',

    CONSTRAINT uq_link_order_user UNIQUE (hub_order_id, hub_user_id),

    FOREIGN KEY (hub_order_id) REFERENCES hub_order(hub_order_id),
    FOREIGN KEY (hub_user_id)  REFERENCES hub_user(hub_user_id)
);

CREATE INDEX IF NOT EXISTS idx_link_order_user_order ON link_order_user(hub_order_id);
CREATE INDEX IF NOT EXISTS idx_link_order_user_user  ON link_order_user(hub_user_id);


-- =========================================
-- LINK: Order - Product
-- =========================================
CREATE TABLE IF NOT EXISTS link_order_product (
    link_order_product_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hub_order_id          UUID NOT NULL,
    hub_product_id        UUID NOT NULL,
    load_date             TIMESTAMP NOT NULL DEFAULT now(),
    record_source         VARCHAR NOT NULL DEFAULT 'order_service',

    CONSTRAINT uq_link_order_product UNIQUE (hub_order_id, hub_product_id),

    FOREIGN KEY (hub_order_id)   REFERENCES hub_order(hub_order_id),
    FOREIGN KEY (hub_product_id) REFERENCES hub_product(hub_product_id)
);

CREATE INDEX IF NOT EXISTS idx_link_order_product_order   ON link_order_product(hub_order_id);
CREATE INDEX IF NOT EXISTS idx_link_order_product_product ON link_order_product(hub_product_id);


-- =========================================
-- LINK: Order - Address
-- =========================================
CREATE TABLE IF NOT EXISTS link_order_address (
    link_order_address_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hub_order_id          UUID NOT NULL,
    hub_address_id        UUID NOT NULL,
    load_date             TIMESTAMP NOT NULL DEFAULT now(),
    record_source         VARCHAR NOT NULL DEFAULT 'order_service',

    CONSTRAINT uq_link_order_address UNIQUE (hub_order_id, hub_address_id),

    FOREIGN KEY (hub_order_id)   REFERENCES hub_order(hub_order_id),
    FOREIGN KEY (hub_address_id) REFERENCES hub_address(hub_address_id)
);

CREATE INDEX IF NOT EXISTS idx_link_order_address_order   ON link_order_address(hub_order_id);
CREATE INDEX IF NOT EXISTS idx_link_order_address_address ON link_order_address(hub_address_id);


-- =========================================
-- LINK: Shipment - Order
-- =========================================
CREATE TABLE IF NOT EXISTS link_shipment_order (
    link_shipment_order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hub_shipment_id        UUID NOT NULL,
    hub_order_id           UUID NOT NULL,
    load_date              TIMESTAMP NOT NULL DEFAULT now(),
    record_source          VARCHAR NOT NULL DEFAULT 'order_service',

    CONSTRAINT uq_link_shipment_order UNIQUE (hub_shipment_id, hub_order_id),

    FOREIGN KEY (hub_shipment_id) REFERENCES hub_shipment(hub_shipment_id),
    FOREIGN KEY (hub_order_id)    REFERENCES hub_order(hub_order_id)
);

CREATE INDEX IF NOT EXISTS idx_link_shipment_order_shipment ON link_shipment_order(hub_shipment_id);
CREATE INDEX IF NOT EXISTS idx_link_shipment_order_order    ON link_shipment_order(hub_order_id);


-- =========================================
-- LINK: Shipment - Warehouse
-- =========================================
CREATE TABLE IF NOT EXISTS link_shipment_warehouse (
    link_shipment_warehouse_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hub_shipment_id            UUID NOT NULL,
    hub_warehouse_id           UUID NOT NULL,
    load_date                  TIMESTAMP NOT NULL DEFAULT now(),
    record_source              VARCHAR NOT NULL DEFAULT 'logistics_service',

    CONSTRAINT uq_link_shipment_warehouse UNIQUE (hub_shipment_id, hub_warehouse_id),

    FOREIGN KEY (hub_shipment_id)  REFERENCES hub_shipment(hub_shipment_id),
    FOREIGN KEY (hub_warehouse_id) REFERENCES hub_warehouse(hub_warehouse_id)
);

CREATE INDEX IF NOT EXISTS idx_link_shipment_warehouse_shipment 
    ON link_shipment_warehouse(hub_shipment_id);

CREATE INDEX IF NOT EXISTS idx_link_shipment_warehouse_warehouse  
    ON link_shipment_warehouse(hub_warehouse_id);


-- =========================================
-- LINK: Shipment - Pickup Point
-- =========================================
CREATE TABLE IF NOT EXISTS link_shipment_pickup (
    link_shipment_pickup_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hub_shipment_id         UUID NOT NULL,
    hub_pickup_point_id     UUID NOT NULL,
    load_date               TIMESTAMP NOT NULL DEFAULT now(),
    record_source           VARCHAR NOT NULL DEFAULT 'logistics_service',

    CONSTRAINT uq_link_shipment_pickup UNIQUE (hub_shipment_id, hub_pickup_point_id),

    FOREIGN KEY (hub_shipment_id)     REFERENCES hub_shipment(hub_shipment_id),
    FOREIGN KEY (hub_pickup_point_id) REFERENCES hub_pickup_point(hub_pickup_point_id)
);

CREATE INDEX IF NOT EXISTS idx_link_shipment_pickup_shipment 
    ON link_shipment_pickup(hub_shipment_id);

CREATE INDEX IF NOT EXISTS idx_link_shipment_pickup_pickup  
    ON link_shipment_pickup(hub_pickup_point_id);


-- =========================================
-- LINK: Address - User
-- =========================================
CREATE TABLE IF NOT EXISTS link_address_user (
    link_address_user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hub_address_id       UUID NOT NULL,
    hub_user_id          UUID NOT NULL,
    load_date            TIMESTAMP NOT NULL DEFAULT now(),
    record_source        VARCHAR NOT NULL DEFAULT 'user_service',

    CONSTRAINT uq_link_address_user UNIQUE (hub_address_id, hub_user_id),

    FOREIGN KEY (hub_address_id) REFERENCES hub_address(hub_address_id),
    FOREIGN KEY (hub_user_id)    REFERENCES hub_user(hub_user_id)
);

CREATE INDEX IF NOT EXISTS idx_link_address_user_address 
    ON link_address_user(hub_address_id);

CREATE INDEX IF NOT EXISTS idx_link_address_user_user  
    ON link_address_user(hub_user_id);
