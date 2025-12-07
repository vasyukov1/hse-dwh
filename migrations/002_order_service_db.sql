\connect order_service_db
SET search_path = public;

CREATE TABLE products (
    product_id              SERIAL      PRIMARY KEY,
    product_sku             VARCHAR     NOT NULL UNIQUE, -- Business Key
    
    -- specification
    product_name            VARCHAR,
    category                VARCHAR,
    brand                   VARCHAR,
    price                   DECIMAL,
    currency                VARCHAR,
    
    -- physical characteristics
    weight_grams            INTEGER,
    dimensions_length_cm    DECIMAL,
    dimensions_width_cm     DECIMAL,
    dimensions_height_cm    DECIMAL,
    is_active               BOOLEAN,

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

CREATE TABLE orders (
    order_id                        SERIAL      PRIMARY KEY,
    order_external_id               UUID        NOT NULL UNIQUE, -- Business Key
    user_external_id                UUID        NOT NULL, -- Business Key

    -- characteristic
    order_number                    VARCHAR     NOT NULL UNIQUE,
    order_date                      TIMESTAMP,
    status                          VARCHAR,

    -- finance
    subtotal                        DECIMAL,
    tax_amount                      DECIMAL,
    shipping_cost                   DECIMAL,
    discount_amount                 DECIMAL,
    total_amount                    DECIMAL,
    currency                        VARCHAR,

    -- delivery
    delivery_address_external_id    UUID        NOT NULL, -- Business Key
    delivery_type                   VARCHAR,
    expected_delivery_date          DATE,
    actual_delivery_date            DATE,
    
    -- payment
    payment_method                  VARCHAR,
    payment_status                  VARCHAR,

    -- SCD Type 2
    effective_from                  TIMESTAMP,
    effective_to                    TIMESTAMP,
    is_current                      BOOLEAN,

    -- audit
    created_at                      TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at                      TIMESTAMP   NOT NULL DEFAULT NOW(),
    created_by                      VARCHAR,
    updated_by                      VARCHAR
);

CREATE TABLE order_items (
    order_item_id               SERIAL      PRIMARY KEY,
    order_external_id           UUID        NOT NULL, -- Business Key
    product_sku                 VARCHAR     NOT NULL, -- Business Key

    -- characteristics
    quantity                    INTEGER,
    unit_price                  DECIMAL,
    total_price                 DECIMAL,

    -- snapshot
    product_name_snapshot       VARCHAR,
    product_category_snapshot   VARCHAR,
    product_brand_snapshot      VARCHAR,

    -- audit
    created_at                  TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMP   NOT NULL DEFAULT NOW(),
    created_by                  VARCHAR,
    updated_by                  VARCHAR,

    -- constraint
    CONSTRAINT fk_order_items_orders
        FOREIGN KEY(order_external_id)
        REFERENCES orders(order_external_id),

    CONSTRAINT fk_order_items_products
        FOREIGN KEY(product_sku)
        REFERENCES products(product_sku)
);

CREATE TABLE order_status_history (
    history_id          SERIAL      PRIMARY KEY,
    order_external_id   UUID        NOT NULL, -- Business Key
    
    -- status
    old_status          VARCHAR,
    new_status          VARCHAR,
    change_reason       VARCHAR,
    
    -- metadata changes
    changed_at          TIMESTAMP   NOT NULL DEFAULT NOW(),
    changed_by          VARCHAR,
    
    -- change context
    session_id          VARCHAR,
    ip_address          INET,
    notes               TEXT,

    -- constraint
    CONSTRAINT fk_order_status_history_orders
        FOREIGN KEY(order_external_id)
        REFERENCES orders(order_external_id)
);
