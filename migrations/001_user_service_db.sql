\connect user_service_db
SET search_path = public;

CREATE TABLE users (
    user_id             SERIAL      PRIMARY KEY,
    user_external_id    UUID        NOT NULL UNIQUE, -- Business Key

    -- personal information
    email               VARCHAR,
    first_name          VARCHAR,
    last_name           VARCHAR,
    phone               VARCHAR,
    date_of_birth       DATE,

    -- account information
    registration_date   TIMESTAMP   NOT NULL DEFAULT NOW(),
    status              VARCHAR,

    -- SCD Type 2
    effective_from      TIMESTAMP,
    effective_to        TIMESTAMP,
    is_current          BOOLEAN,

    -- audit
    created_at          TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP   NOT NULL DEFAULT NOW(),
    created_by          VARCHAR,
    updated_by          VARCHAR
);

CREATE TABLE user_addresses (
    address_id          SERIAL  PRIMARY KEY,
    address_external_id UUID    NOT NULL UNIQUE, -- Business Key
    user_external_id    UUID    NOT NULL, -- Business Key

    -- address
    address_type        VARCHAR,
    country             VARCHAR,
    region              VARCHAR,
    city                VARCHAR,
    street_address      VARCHAR,
    postal_code         VARCHAR,
    apartment           VARCHAR,
    is_default          BOOLEAN,

    -- SCD Type 2
    effective_from      TIMESTAMP,
    effective_to        TIMESTAMP,
    is_current          BOOLEAN,

    -- audit
    created_at          TIMESTAMP   NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP   NOT NULL DEFAULT NOW(),
    created_by          VARCHAR,
    updated_by          VARCHAR,

    -- constraint
    CONSTRAINT fk_user_addresses_users
        FOREIGN KEY(user_external_id)
        REFERENCES users(user_external_id)
);

CREATE TABLE user_status_history (
    history_id          SERIAL      PRIMARY KEY,
    user_external_id    UUID        NOT NULL,
    
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
    user_agent          TEXT,

    -- constraint
    CONSTRAINT fk_user_status_history_users
        FOREIGN KEY(user_external_id)
        REFERENCES users(user_external_id)
);