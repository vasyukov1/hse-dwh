\connect logistics_service_db
SET search_path = public;

CREATE TABLE IF NOT EXISTS warehouses (
    warehouse_id                SERIAL      PRIMARY KEY,
    warehouse_code              VARCHAR     NOT NULL UNIQUE, -- Business Key
    warehouse_name              VARCHAR,
    warehouse_type              VARCHAR,
    
    -- address
    country                     VARCHAR,
    region                      VARCHAR,
    city                        VARCHAR,
    street_address              VARCHAR,
    postal_code                 VARCHAR,
    is_active                   BOOLEAN,

    -- characteristics
    max_capacity_cubic_meters   DECIMAL,
    operating_hours             VARCHAR,
    contact_phone               VARCHAR,
    manager_name                VARCHAR,

    -- SCD Type 2
    effective_from              TIMESTAMP,
    effective_to                TIMESTAMP,
    is_current                  BOOLEAN,

    -- audit
    created_at                  TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMP   NOT NULL DEFAULT NOW(),
    created_by                  VARCHAR,
    updated_by                  VARCHAR
);

CREATE TABLE IF NOT EXISTS pickup_points (
    pickup_point_id         SERIAL      PRIMARY KEY,
    pickup_point_code       VARCHAR     NOT NULL UNIQUE, -- Business Key
    pickup_point_name       VARCHAR,
    pickup_point_type       VARCHAR,

    -- address
    country                 VARCHAR,
    region                  VARCHAR,
    city                    VARCHAR,
    street_address          VARCHAR,
    postal_code             VARCHAR,
    is_active               BOOLEAN,

    -- characteristics
    max_capacity_packages   INTEGER,
    operating_hours         VARCHAR,
    contact_phone           VARCHAR,
    partner_name            VARCHAR,
    
    -- SCD Type 2
    effective_from          TIMESTAMP,
    effective_to            TIMESTAMP,
    is_current              BOOLEAN,

    -- audit
    created_at              TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMP   NOT NULL DEFAULT NOW(),
    created_by              VARCHAR,
    updated_by              VARCHAR
);

CREATE TABLE IF NOT EXISTS shipments (
    shipment_id                     SERIAL      PRIMARY KEY,
    shipment_external_id            UUID        NOT NULL UNIQUE, -- Business Key
    order_external_id               UUID        NOT NULL,

    -- characteristics
    tracking_number                 VARCHAR     NOT NULL UNIQUE,
    status                          VARCHAR,
    weight_grams                    INTEGER,
    volume_cubic_cm                 INTEGER,
    package_count                   INTEGER,
    origin_warehouse_code           VARCHAR     NOT NULL,
    
    -- destination
    destination_type                VARCHAR,
    destination_pickup_point_code   VARCHAR,
    destination_address_external_id UUID,
    
    -- dates
    created_date                    TIMESTAMP   NOT NULL DEFAULT NOW(),
    dispatched_date                 TIMESTAMP,
    estimated_delivery_date         TIMESTAMP,
    actual_delivery_date            TIMESTAMP,

    -- additional information
    delivery_notes                  TEXT,
    recipient_name                  VARCHAR,
    delivery_signature              VARCHAR,

    -- SCD Type 2
    effective_from                  TIMESTAMP,
    effective_to                    TIMESTAMP,
    is_current                      BOOLEAN,

    -- audit
    created_at                      TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at                      TIMESTAMP   NOT NULL DEFAULT NOW(),
    created_by                      VARCHAR,
    updated_by                      VARCHAR,

    -- constraint
    CONSTRAINT fk_shipments_warehouses
        FOREIGN KEY(origin_warehouse_code)
        REFERENCES warehouses(warehouse_code),

    CONSTRAINT fk_shipments_pickup_points
        FOREIGN KEY(destination_pickup_point_code)
        REFERENCES pickup_points(pickup_point_code)
);

CREATE TABLE IF NOT EXISTS shipment_movements (
    movement_id             SERIAL      PRIMARY KEY,
    shipment_external_id    UUID        NOT NULL,

    -- information
    movement_type           VARCHAR,
    location_type           VARCHAR,
    location_code           VARCHAR,
    movement_datetime       TIMESTAMP,
    operator_name           VARCHAR,
    notes                   TEXT,
    
    -- geolocation
    latitude                DECIMAL,
    longitude               DECIMAL,
    
    -- audit
    created_at              TIMESTAMP   NOT NULL DEFAULT NOW(),
    created_by              VARCHAR,

    -- constraint
    CONSTRAINT fk_shipment_movements_shipments
        FOREIGN KEY(shipment_external_id)
        REFERENCES shipments(shipment_external_id)
);

CREATE TABLE IF NOT EXISTS shipment_status_history (
    history_id              SERIAL      PRIMARY KEY,
    shipment_external_id    UUID        NOT NULL,

    -- status
    old_status              VARCHAR,
    new_status              VARCHAR,
    change_reason           VARCHAR,
    
    -- metadata changes
    changed_at              TIMESTAMP   NOT NULL DEFAULT NOW(),
    changed_by              VARCHAR,

    -- change context
    location_type           VARCHAR,
    location_code           VARCHAR,
    notes                   TEXT,
    customer_notified       BOOLEAN,

    -- constraint
    CONSTRAINT fk_shipment_status_history_shipments
        FOREIGN KEY(shipment_external_id)
        REFERENCES shipments(shipment_external_id)
);
