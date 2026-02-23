# HUB

## hub_user
- user_external_id (business key)
- user_hashkey
- load_date
- record_source

## hub_address
- address_external_id (business key)
- address_hashkey
- load_date
- record_source

## hub_order
- order_external_id (business key)
- order_hashkey
- load_date
- record_source

## hub_product
- product_sku (business key)
- product_hashkey
- load_date
- record_source

## hub_warehouse
- warehouse_code (business key)
- warehouse_hashkey
- load_date
- record_source

## hub_pickup_point
- pickup_point_code (business key)
- pickup_point_hashkey
- load_date
- record_source

## hub_shipment
- shipment_external_id (business key)
- shipment_hashkey
- load_date
- record_source


# LINKS

## link_user_address
- link_user_address_hashkey
- user_hashkey
- address_hashkey
- load_date
- record_source

## link_order_user
- link_order_user_hashkey
- order_hashkey
- user_hashkey
- load_date
- record_source

## link_order_address
- link_order_address_hashkey
- order_hashkey
- address_hashkey
- load_date
- record_source

## link_order_product
- link_order_product_hashkey
- order_hashkey
- product_hashkey
- load_date
- record_source

## link_shipment_order
- link_shipment_order_hashkey
- shipment_hashkey
- order_hashkey
- load_date
- record_source

## link_shipment_warehouse
- link_shipment_warehouse_hashkey
- shipment_hashkey
- warehouse_hashkey
- load_date
- record_source

## link_shipment_pickup_point
- link_shipment_pickup_point_hashkey
- shipment_hashkey
- pickup_point_hashkey
- load_date
- record_source

## link_shipment_address
- link_shipment_address_hashkey
- shipment_hashkey
- address_hashkey
- load_date
- record_source


# SATELLITES

## sat_user_details (hub_user)
- user_hashkey
- email
- first_name
- last_name
- phone
- date_of_birth
- registration_date
- status
- hash_diff
- load_date
- record_source
- effective_from
- effective_to
- is_current
- created_at
- updated_at
- created_by
- updated_by

## sat_address_details (hub_address)
- address_hashkey
- address_type
- country
- region
- city
- street_address
- postal_code
- hash_diff
- load_date
- record_source

## sat_order_header (hub_order)
- order_hashkey
- order_date
- status
- subtotal
- tax_amount
- shipping_cost
- discount_amount
- total_amount
- currency
- hash_diff
- load_date
- record_source

## sat_product_details (hub_product)
- product_hashkey
- product_name
- category
- brand
- price
- currency
- weight_grams
- dimensions
- hash_diff
- load_date
- record_source

## sat_warehouse_details (hub_warehouse)
- warehouse_hashkey
- warehouse_name
- warehouse_type
- country
- region
- city
- max_capacity
- hash_diff
- load_date
- record_source

## sat_pickup_point_details (hub_pickup_point)
- pickup_point_hashkey
- pickup_point_name
- pickup_point_type
- country
- region
- city
- max_capacity
- hash_diff
- load_date
- record_source

## sat_shipment_details (hub_shipment)
- shipment_hashkey
- status
- weight_grams
- volume_cubic_cm
- package_count
- estimated_delivery_date
- actual_delivery_date
- tracking_number
- hash_diff
- load_date
- record_source

## sat_order_line (link_order_product)
- link_order_product_hashkey
- quantity
- unit_price
- line_total
- discount_amount
- currency
- hash_diff
- load_date
- record_source
- product_name_snapshot
- product_category_snapshot
- product_brand_snapshot
- created_at
- updated_at
- created_by
- updated_by

## sat_user_address_details (link_user_address)
- link_user_address_hashkey
- is_primary
- valid_from
- valid_to
- hash_diff
- load_date
- record_source

## sat_order_address_details (link_order_address)
- link_order_address_hashkey
- address_type
- hash_diff
- load_date
- record_source

## sat_shipment_order_details (link_shipment_order)
- link_shipment_order_hashkey
- shipped_date
- hash_diff
- load_date
- record_source

## sat_shipment_warehouse_details (link_shipment_warehouse)
- link_shipment_warehouse_hashkey
- dispatch_date
- hash_diff
- load_date
- record_source

## sat_shipment_pickup_point_details (link_shipment_pickup_point)
- link_shipment_pickup_point_hashkey
- available_from
- hash_diff
- load_date
- record_source

## sat_shipment_address_details (link_shipment_address)
- link_shipment_address_hashkey
- delivery_attempts
- delivered_date
- hash_diff
- load_date
- record_source
