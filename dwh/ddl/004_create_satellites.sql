-- =========================================
-- SATELLITE: User details
-- =========================================
CREATE TABLE IF NOT EXISTS sat_user_details (
    hub_user_id        UUID NOT NULL,
    load_date          TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date      TIMESTAMP,

    email              VARCHAR,
    first_name         VARCHAR,
    last_name          VARCHAR,
    phone              VARCHAR,
    date_of_birth      DATE,
    registration_date  TIMESTAMP,
    status             VARCHAR,
    is_current         BOOLEAN,
    effective_from     TIMESTAMP,
    effective_to       TIMESTAMP,
    created_at         TIMESTAMP,
    updated_at         TIMESTAMP,
    created_by         VARCHAR,
    updated_by         VARCHAR,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'user_service',

    FOREIGN KEY (hub_user_id) REFERENCES hub_user(hub_user_id),
    PRIMARY KEY (hub_user_id, load_date)
);


-- =========================================
-- SATELLITE: User address details
-- =========================================
CREATE TABLE IF NOT EXISTS sat_user_address_details (
    hub_user_address_id UUID NOT NULL,
    hub_user_id         UUID NOT NULL,
    load_date           TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date       TIMESTAMP,

    address_type     VARCHAR,
    country          VARCHAR,
    region           VARCHAR,
    city             VARCHAR,
    street_address   VARCHAR,
    postal_code      VARCHAR,
    apartment        VARCHAR,
    is_default       BOOLEAN,
    is_current       BOOLEAN,
    effective_from   TIMESTAMP,
    effective_to     TIMESTAMP,
    created_at       TIMESTAMP,
    updated_at       TIMESTAMP,
    created_by       VARCHAR,
    updated_by       VARCHAR,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'user_service',

    FOREIGN KEY (hub_user_address_id) REFERENCES hub_user_address(hub_user_address_id),
    FOREIGN KEY (hub_user_id) REFERENCES hub_user(hub_user_id),
    PRIMARY KEY (hub_user_address_id, load_date)
);


-- =========================================
-- SATELLITE: User status history
-- =========================================
CREATE TABLE IF NOT EXISTS sat_user_status_history (
    hub_user_id    UUID NOT NULL,
    load_date      TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date  TIMESTAMP,

    old_status     VARCHAR,
    new_status     VARCHAR,
    change_reason  VARCHAR,
    changed_at     TIMESTAMP,
    changed_by     VARCHAR,
    session_id     VARCHAR,
    ip_address     INET,
    user_agent     TEXT,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'user_service',

    FOREIGN KEY (hub_user_id) REFERENCES hub_user(hub_user_id),
    PRIMARY KEY (hub_user_id, load_date)
);


-- =========================================
-- SATELLITE: Product details
-- =========================================
CREATE TABLE IF NOT EXISTS sat_product_details (
    hub_product_id UUID NOT NULL,
    load_date      TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date  TIMESTAMP,

    product_sku    VARCHAR,
    product_name   VARCHAR,
    category       VARCHAR,
    brand          VARCHAR,
    price          DECIMAL,
    currency       VARCHAR,
    weight_grams   INTEGER,
    dimensions_length_cm  DECIMAL,
    dimensions_width_cm   DECIMAL,
    dimensions_height_cm  DECIMAL,
    is_active      BOOLEAN,
    effective_from TIMESTAMP,
    effective_to   TIMESTAMP,
    is_current     BOOLEAN,
    created_at     TIMESTAMP,
    updated_at     TIMESTAMP,
    created_by     VARCHAR,
    updated_by     VARCHAR,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'product_service',

    FOREIGN KEY (hub_product_id) REFERENCES hub_product(hub_product_id),
    PRIMARY KEY (hub_product_id, load_date)
);


-- =========================================
-- SATELLITE: Order details
-- =========================================
CREATE TABLE IF NOT EXISTS sat_order_details (
    hub_order_id    UUID NOT NULL,
    load_date       TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date   TIMESTAMP,

    order_external_id UUID,
    order_number            VARCHAR,
    order_date              TIMESTAMP,
    status                  VARCHAR,
    subtotal                DECIMAL,
    tax_amount              DECIMAL,
    shipping_cost           DECIMAL,
    discount_amount         DECIMAL,
    total_amount            DECIMAL,
    currency                VARCHAR,
    delivery_address_external_id UUID,
    delivery_type           VARCHAR,
    expected_delivery_date  DATE,
    actual_delivery_date    DATE,
    payment_method          VARCHAR,
    payment_status          VARCHAR,
    effective_from          TIMESTAMP,
    effective_to            TIMESTAMP,
    is_current              BOOLEAN,
    created_at              TIMESTAMP,
    updated_at              TIMESTAMP,
    created_by              VARCHAR,
    updated_by              VARCHAR,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'order_service',

    FOREIGN KEY (hub_order_id) REFERENCES hub_order(hub_order_id),
    PRIMARY KEY (hub_order_id, load_date)
);


-- =========================================
-- SATELLITE: Order item snapshot
-- =========================================
CREATE TABLE IF NOT EXISTS sat_order_item_snapshot (
    lnk_order_product_id UUID NOT NULL,
    load_date            TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date        TIMESTAMP,

    order_external_id    UUID,
    product_sku          VARCHAR,
    quantity             INTEGER,
    unit_price           DECIMAL,
    total_price          DECIMAL,
    product_name_snapshot     VARCHAR,
    product_category_snapshot VARCHAR,
    product_brand_snapshot    VARCHAR,
    created_at           TIMESTAMP,
    updated_at           TIMESTAMP,
    created_by           VARCHAR,
    updated_by           VARCHAR,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'order_service',

    FOREIGN KEY (lnk_order_product_id) REFERENCES lnk_order_product(lnk_order_product_id),
    PRIMARY KEY (lnk_order_product_id, load_date)
);


-- =========================================
-- SATELLITE: Order status history
-- =========================================
CREATE TABLE IF NOT EXISTS sat_order_status_history (
    hub_order_id   UUID NOT NULL,
    load_date      TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date  TIMESTAMP,

    old_status     VARCHAR,
    new_status     VARCHAR,
    change_reason  VARCHAR,
    changed_at     TIMESTAMP,
    changed_by     VARCHAR,
    session_id     VARCHAR,
    ip_address     INET,
    notes          TEXT,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'order_service',

    FOREIGN KEY (hub_order_id) REFERENCES hub_order(hub_order_id),
    PRIMARY KEY (hub_order_id, load_date)
);


-- =========================================
-- SATELLITE: Warehouse details
-- =========================================
CREATE TABLE IF NOT EXISTS sat_warehouse_details (
    hub_warehouse_id UUID NOT NULL,
    load_date        TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date    TIMESTAMP,

    warehouse_code          VARCHAR,
    warehouse_name          VARCHAR,
    warehouse_type          VARCHAR,
    country                 VARCHAR,
    region                  VARCHAR,
    city                    VARCHAR,
    street_address          VARCHAR,
    postal_code             VARCHAR,
    is_active               BOOLEAN,
    max_capacity_cubic_meters  DECIMAL,
    operating_hours         VARCHAR,
    contact_phone           VARCHAR,
    manager_name            VARCHAR,
    effective_from          TIMESTAMP,
    effective_to            TIMESTAMP,
    is_current              BOOLEAN,
    created_at              TIMESTAMP,
    updated_at              TIMESTAMP,
    created_by              VARCHAR,
    updated_by              VARCHAR,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'logistics_service',

    FOREIGN KEY (hub_warehouse_id) REFERENCES hub_warehouse(hub_warehouse_id),
    PRIMARY KEY (hub_warehouse_id, load_date)
);


-- =========================================
-- SATELLITE: Pickup point details
-- =========================================
CREATE TABLE IF NOT EXISTS sat_pickup_point_details (
    hub_pickup_point_id UUID NOT NULL,
    load_date           TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date       TIMESTAMP,

    pickup_point_code  VARCHAR,
    pickup_point_name  VARCHAR,
    pickup_point_type  VARCHAR,
    country            VARCHAR,
    region             VARCHAR,
    city               VARCHAR,
    street_address     VARCHAR,
    postal_code        VARCHAR,
    is_active          BOOLEAN,
    max_capacity_packages INTEGER,
    operating_hours    VARCHAR,
    contact_phone      VARCHAR,
    partner_name       VARCHAR,
    effective_from     TIMESTAMP,
    effective_to       TIMESTAMP,
    is_current         BOOLEAN,
    created_at         TIMESTAMP,
    updated_at         TIMESTAMP,
    created_by         VARCHAR,
    updated_by         VARCHAR,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'logistics_service',

    FOREIGN KEY (hub_pickup_point_id) REFERENCES hub_pickup_point(hub_pickup_point_id),
    PRIMARY KEY (hub_pickup_point_id, load_date)
);


-- =========================================
-- SATELLITE: Shipment details
-- =========================================
CREATE TABLE IF NOT EXISTS sat_shipment_details (
    hub_shipment_id UUID NOT NULL,
    load_date       TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date   TIMESTAMP,

    shipment_external_id UUID,
    order_external_id    UUID,
    tracking_number      VARCHAR,
    status               VARCHAR,
    weight_grams         INTEGER,
    volume_cubic_cm      INTEGER,
    package_count        INTEGER,
    origin_warehouse_code VARCHAR,
    destination_type     VARCHAR,
    destination_pickup_point_code VARCHAR,
    destination_address_external_id UUID,
    created_date         TIMESTAMP,
    dispatched_date      TIMESTAMP,
    estimated_delivery_date TIMESTAMP,
    actual_delivery_date TIMESTAMP,
    delivery_notes       TEXT,
    recipient_name       VARCHAR,
    delivery_signature   VARCHAR,
    effective_from       TIMESTAMP,
    effective_to         TIMESTAMP,
    is_current           BOOLEAN,
    created_at           TIMESTAMP,
    updated_at           TIMESTAMP,
    created_by           VARCHAR,
    updated_by           VARCHAR,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'logistics_service',

    FOREIGN KEY (hub_shipment_id) REFERENCES hub_shipment(hub_shipment_id),
    PRIMARY KEY (hub_shipment_id, load_date)
);


-- =========================================
-- SATELLITE: Shipment movement history
-- =========================================
CREATE TABLE IF NOT EXISTS sat_shipment_movements (
    hub_shipment_id   UUID NOT NULL,
    load_date         TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date     TIMESTAMP,

    movement_type     VARCHAR,
    location_type     VARCHAR,
    location_code     VARCHAR,
    movement_datetime TIMESTAMP,
    operator_name     VARCHAR,
    notes             TEXT,
    latitude          DECIMAL,
    longitude         DECIMAL,
    created_at        TIMESTAMP,
    created_by        VARCHAR,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'logistics_service',

    FOREIGN KEY (hub_shipment_id) REFERENCES hub_shipment(hub_shipment_id),
    PRIMARY KEY (hub_shipment_id, load_date)
);


-- =========================================
-- SATELLITE: Shipment status history
-- =========================================
CREATE TABLE IF NOT EXISTS sat_shipment_status_history (
    hub_shipment_id UUID NOT NULL,
    load_date       TIMESTAMP NOT NULL DEFAULT now(),
    load_end_date   TIMESTAMP,

    old_status      VARCHAR,
    new_status      VARCHAR,
    change_reason   VARCHAR,
    changed_at      TIMESTAMP,
    changed_by      VARCHAR,
    location_type   VARCHAR,
    location_code   VARCHAR,
    notes           TEXT,
    customer_notified BOOLEAN,

    hash_diff      VARCHAR(128) NOT NULL,
    record_source  VARCHAR NOT NULL DEFAULT 'logistics_service',

    FOREIGN KEY (hub_shipment_id) REFERENCES hub_shipment(hub_shipment_id),
    PRIMARY KEY (hub_shipment_id, load_date)
);
