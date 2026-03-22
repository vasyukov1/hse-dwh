from __future__ import annotations

import hashlib
import logging
import os
import time
from datetime import datetime, timedelta

import pymysql
import psycopg2
from airflow import DAG
from airflow.operators.python import PythonOperator

log = logging.getLogger(__name__)

# ── StarRocks connection params ────────────────────────────────
_SR = dict(
    host=os.getenv("STARROCKS_HOST", "starrocks"),
    port=int(os.getenv("STARROCKS_PORT", "9030")),
    user=os.getenv("STARROCKS_USER", "root"),
    password=os.getenv("STARROCKS_PASSWORD", ""),
    charset="utf8mb4",
    connect_timeout=30,
    autocommit=True,
)

_PG = dict(
    host=os.getenv("SRC_PG_HOST", "postgres-replica"),
    port=int(os.getenv("SRC_PG_PORT", "5432")),
    user=os.getenv("POSTGRES_USER", "postgres"),
    password=os.getenv("POSTGRES_PASSWORD", "postgres"),
    connect_timeout=30,
)


def _conn(db: str) -> pymysql.Connection:
    return pymysql.connect(database=db, **_SR)


def _pg_conn(db: str):
    return psycopg2.connect(dbname=db, **_PG)


def _exec(conn, sql: str) -> None:
    with conn.cursor() as cur:
        cur.execute(sql)


def _count(conn, sql: str) -> int:
    with conn.cursor() as cur:
        cur.execute(sql)
        r = cur.fetchone()
        return int(r[0]) if r else 0


def _pg_count(conn, sql: str, params=None) -> int:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        r = cur.fetchone()
        return int(r[0]) if r else 0


def _pg_rows(conn, sql: str, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def _stable_int(value: str | None) -> int:
    data = (value or "unknown").encode("utf-8")
    return int(hashlib.md5(data).hexdigest()[:8], 16) % 2147483647


def _insert_rows_robust(conn, sql: str, payload: list[tuple], label: str) -> None:
    total = len(payload)
    batch_size = 1000
    retry_sleep_sec = 2
    max_retry_attempts = 30
    for start in range(0, total, batch_size):
        chunk = payload[start:start + batch_size]
        for attempt in range(max_retry_attempts):
            try:
                conn.ping(reconnect=True)
                with conn.cursor() as cur:
                    cur.executemany(sql, chunk)
                break
            except (pymysql.err.OperationalError, pymysql.err.InterfaceError) as exc:
                if attempt == max_retry_attempts - 1:
                    raise
                log.warning(
                    "[%s] StarRocks connection issue during batch %d-%d/%d: %s. Retrying in %ds (%d/%d)",
                    label,
                    start + 1,
                    start + len(chunk),
                    total,
                    exc,
                    retry_sleep_sec,
                    attempt + 1,
                    max_retry_attempts,
                )
                time.sleep(retry_sleep_sec)
        inserted = min(start + len(chunk), total)
        if inserted % 5000 == 0 or inserted == total:
            log.info("[%s] inserted %d/%d rows", label, inserted, total)


def _use_dwh_for_purchase(sr_conn) -> bool:
    dwh_count = _count(sr_conn, "SELECT COUNT(*) FROM dwh_detailed.sat_order_items")
    with _pg_conn("order_service_db") as pg_conn:
        src_count = _pg_count(pg_conn, "SELECT COUNT(*) FROM order_items")

    ready = src_count > 0 and dwh_count >= src_count
    log.info("[purchase] DWH readiness: sat_order_items=%d, source_order_items=%d", dwh_count, src_count)
    return ready


def _use_dwh_for_delivery(sr_conn) -> bool:
    dwh_count = _count(
        sr_conn,
        """
        SELECT COUNT(*)
        FROM dwh_detailed.sat_shipments
        WHERE dispatched_date IS NOT NULL
        """,
    )
    with _pg_conn("logistics_service_db") as pg_conn:
        src_count = _pg_count(
            pg_conn,
            """
            SELECT COUNT(*)
            FROM shipments
            WHERE dispatched_date IS NOT NULL
            """,
        )

    ready = src_count > 0 and dwh_count >= src_count
    log.info("[delivery] DWH readiness: sat_shipments=%d, source_shipments=%d", dwh_count, src_count)
    return ready


# ═══════════════════════════════════════════════════════════════
# MART 1: dm_purchase_analytics
# ═══════════════════════════════════════════════════════════════
# purchase_date  — дата заказа
# product_id     — числовой хэш product_sku
# supplier_id    — числовой хэш бренда
# ───────────────────────────────────────────────────────────────

_SQL_PURCHASE = """
WITH latest_products AS (
    SELECT
        hk_products,
        product_name,
        category,
        brand
    FROM (
        SELECT
            hk_products,
            product_name,
            category,
            brand,
            ROW_NUMBER() OVER (
                PARTITION BY hk_products
                ORDER BY load_dt DESC, hash_diff DESC
            ) AS rn
        FROM dwh_detailed.sat_products
    ) src
    WHERE rn = 1
),
latest_orders AS (
    SELECT
        hk_orders,
        order_date,
        status
    FROM (
        SELECT
            hk_orders,
            order_date,
            status,
            ROW_NUMBER() OVER (
                PARTITION BY hk_orders
                ORDER BY load_dt DESC, hash_diff DESC
            ) AS rn
        FROM dwh_detailed.sat_orders
    ) src
    WHERE rn = 1
),
latest_order_items AS (
    SELECT
        hk_lnk_order_items,
        quantity,
        unit_price,
        total_price,
        product_name_snapshot,
        product_category_snapshot,
        product_brand_snapshot
    FROM (
        SELECT
            hk_lnk_order_items,
            quantity,
            unit_price,
            total_price,
            product_name_snapshot,
            product_category_snapshot,
            product_brand_snapshot,
            ROW_NUMBER() OVER (
                PARTITION BY hk_lnk_order_items
                ORDER BY load_dt DESC, hash_diff DESC
            ) AS rn
        FROM dwh_detailed.sat_order_items
    ) src
    WHERE rn = 1
)
INSERT INTO presentation.dm_purchase_analytics
    (purchase_date, product_id, supplier_id,
     product_name, category, supplier_name,
     purchase_qty, total_purchase_amount, avg_unit_price, load_dt)

SELECT
    DATE(so.order_date)                                                  AS purchase_date,

    CAST(
        MOD(CAST(CONV(SUBSTRING(hp.hk_products, 1, 8), 16, 10) AS BIGINT), 2147483647)
        AS INT
    )                                                                    AS product_id,

    CAST(
        MOD(
            CAST(
                CONV(
                    SUBSTRING(MD5(COALESCE(sp.brand, soi.product_brand_snapshot, 'unknown')), 1, 8),
                    16,
                    10
                ) AS BIGINT
            ),
            2147483647
        ) AS INT
    )                                                                    AS supplier_id,

    COALESCE(sp.product_name, soi.product_name_snapshot, 'Unknown')      AS product_name,
    COALESCE(sp.category,     soi.product_category_snapshot, 'Unknown')  AS category,
    COALESCE(sp.brand,        soi.product_brand_snapshot,    'Unknown')  AS supplier_name,

    SUM(COALESCE(soi.quantity,    0))                                     AS purchase_qty,
    SUM(COALESCE(soi.total_price, 0))                                     AS total_purchase_amount,
    CASE
        WHEN SUM(COALESCE(soi.quantity, 0)) = 0 THEN NULL
        ELSE SUM(COALESCE(soi.total_price, 0)) / SUM(COALESCE(soi.quantity, 0))
    END                                                                   AS avg_unit_price,

    NOW()                                                                 AS load_dt

FROM dwh_detailed.lnk_order_items     loi
LEFT JOIN latest_order_items          soi ON soi.hk_lnk_order_items = loi.hk_lnk_order_items
JOIN dwh_detailed.hub_orders          ho  ON ho.hk_orders            = loi.hk_orders
JOIN latest_orders                    so  ON so.hk_orders            = ho.hk_orders
JOIN dwh_detailed.hub_products        hp  ON hp.hk_products          = loi.hk_products
LEFT JOIN latest_products             sp  ON sp.hk_products          = hp.hk_products

WHERE so.order_date IS NOT NULL
  AND COALESCE(LOWER(so.status), '') NOT IN ('cancelled', 'canceled')

GROUP BY
    DATE(so.order_date),
    hp.hk_products,
    COALESCE(sp.product_name, soi.product_name_snapshot, 'Unknown'),
    COALESCE(sp.category,     soi.product_category_snapshot, 'Unknown'),
    COALESCE(sp.brand,        soi.product_brand_snapshot,    'Unknown')
"""

_SQL_PURCHASE_SOURCE = """
SELECT
    DATE(o.order_date) AS purchase_date,
    oi.product_sku,
    COALESCE(p.product_name, oi.product_name_snapshot, 'Unknown') AS product_name,
    COALESCE(p.category, oi.product_category_snapshot, 'Unknown') AS category,
    COALESCE(p.brand, oi.product_brand_snapshot, 'Unknown') AS supplier_name,
    SUM(COALESCE(oi.quantity, 0)) AS purchase_qty,
    SUM(COALESCE(oi.total_price, 0)) AS total_purchase_amount,
    CASE
        WHEN SUM(COALESCE(oi.quantity, 0)) = 0 THEN NULL
        ELSE SUM(COALESCE(oi.total_price, 0)) / SUM(COALESCE(oi.quantity, 0))
    END AS avg_unit_price
FROM order_items oi
JOIN orders o
  ON o.order_external_id = oi.order_external_id
LEFT JOIN products p
  ON p.product_sku = oi.product_sku
WHERE o.order_date IS NOT NULL
  AND COALESCE(LOWER(o.status), '') NOT IN ('cancelled', 'canceled')
GROUP BY
    DATE(o.order_date),
    oi.product_sku,
    COALESCE(p.product_name, oi.product_name_snapshot, 'Unknown'),
    COALESCE(p.category, oi.product_category_snapshot, 'Unknown'),
    COALESCE(p.brand, oi.product_brand_snapshot, 'Unknown')
"""


def _load_purchase_from_source(sr_conn) -> int:
    with _pg_conn("order_service_db") as pg_conn:
        rows = _pg_rows(pg_conn, _SQL_PURCHASE_SOURCE)

    payload = [
        (
            purchase_date,
            _stable_int(product_sku),
            _stable_int(supplier_name),
            product_name,
            category,
            supplier_name,
            purchase_qty,
            total_purchase_amount,
            avg_unit_price,
            datetime.utcnow(),
        )
        for (
            purchase_date,
            product_sku,
            product_name,
            category,
            supplier_name,
            purchase_qty,
            total_purchase_amount,
            avg_unit_price,
        ) in rows
    ]

    if not payload:
        return 0

    _insert_rows_robust(
        sr_conn,
        """
        INSERT INTO presentation.dm_purchase_analytics
            (purchase_date, product_id, supplier_id,
             product_name, category, supplier_name,
             purchase_qty, total_purchase_amount, avg_unit_price, load_dt)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        payload,
        "purchase_source",
    )
    return len(payload)


def refresh_purchase_analytics(ds: str, **_):
    conn = _conn("presentation")
    try:
        log.info("[purchase] Truncating dm_purchase_analytics...")
        _exec(conn, "TRUNCATE TABLE presentation.dm_purchase_analytics")

        if _use_dwh_for_purchase(conn):
            log.info("[purchase] Building mart from dwh_detailed...")
            _exec(conn, _SQL_PURCHASE)
        else:
            log.warning("[purchase] DWH is not fully ready; falling back to source PostgreSQL tables.")
            _load_purchase_from_source(conn)

        n = _count(conn, "SELECT COUNT(*) FROM presentation.dm_purchase_analytics")
        log.info("[purchase] Done. Rows inserted: %d  (ds=%s)", n, ds)
    finally:
        conn.close()


# ═══════════════════════════════════════════════════════════════
# MART 2: dm_warehouse_delivery 
# ═══════════════════════════════════════════════════════════════
# shipment_date           — дата отгрузки (или создания)
# warehouse_id            — числовой хэш warehouse_code
# order_count             — число уникальных заказов
# total_shipment_qty      — сумма package_count
# avg_processing_time_min — ср. минут заказ→отгрузка
# delayed_orders_count    — число уникальных заказов с просрочкой
# unique_customers_count  — уникальных hk_users
# ───────────────────────────────────────────────────────────────

_SQL_DELIVERY = """
WITH latest_shipments AS (
    SELECT
        hk_shipments,
        package_count,
        created_date,
        dispatched_date,
        estimated_delivery_date,
        actual_delivery_date
    FROM (
        SELECT
            hk_shipments,
            package_count,
            created_date,
            dispatched_date,
            estimated_delivery_date,
            actual_delivery_date,
            ROW_NUMBER() OVER (
                PARTITION BY hk_shipments
                ORDER BY load_dt DESC, hash_diff DESC
            ) AS rn
        FROM dwh_detailed.sat_shipments
    ) src
    WHERE rn = 1
),
latest_warehouses AS (
    SELECT
        hk_warehouses,
        warehouse_name
    FROM (
        SELECT
            hk_warehouses,
            warehouse_name,
            ROW_NUMBER() OVER (
                PARTITION BY hk_warehouses
                ORDER BY load_dt DESC, hash_diff DESC
            ) AS rn
        FROM dwh_detailed.sat_warehouses
    ) src
    WHERE rn = 1
),
latest_orders AS (
    SELECT
        hk_orders,
        order_date
    FROM (
        SELECT
            hk_orders,
            order_date,
            ROW_NUMBER() OVER (
                PARTITION BY hk_orders
                ORDER BY load_dt DESC, hash_diff DESC
            ) AS rn
        FROM dwh_detailed.sat_orders
    ) src
    WHERE rn = 1
),
shipment_facts AS (
    SELECT
        CAST('{d}' AS DATE)                                                AS shipment_date,
        CAST(
            MOD(CAST(CONV(SUBSTRING(hw.hk_warehouses, 1, 8), 16, 10) AS BIGINT), 2147483647)
            AS INT
        )                                                                  AS warehouse_id,
        COALESCE(sw.warehouse_name, hw.warehouse_code)                      AS warehouse_name,
        hs.hk_shipments,
        ho.hk_orders,
        lou.hk_users,
        COALESCE(ss.package_count, 0)                                       AS package_count,
        CASE
            WHEN ss.dispatched_date IS NOT NULL AND so.order_date IS NOT NULL
            THEN TIMESTAMPDIFF(MINUTE, so.order_date, ss.dispatched_date)
        END                                                                 AS processing_time_min,
        CASE
            WHEN ss.created_date IS NOT NULL
             AND ss.dispatched_date IS NOT NULL
             AND TIMESTAMPDIFF(HOUR, ss.created_date, ss.dispatched_date) > 24
            THEN 1 ELSE 0
        END                                                                 AS is_delayed
    FROM dwh_detailed.lnk_shipments_warehouses   lsw
    JOIN dwh_detailed.hub_warehouses             hw   ON hw.hk_warehouses = lsw.hk_warehouses
    JOIN dwh_detailed.hub_shipments              hs   ON hs.hk_shipments  = lsw.hk_shipments
    JOIN latest_shipments                        ss   ON ss.hk_shipments  = hs.hk_shipments
    LEFT JOIN latest_warehouses                  sw   ON sw.hk_warehouses = hw.hk_warehouses
    LEFT JOIN dwh_detailed.lnk_shipments_orders  lso  ON lso.hk_shipments = hs.hk_shipments
    LEFT JOIN dwh_detailed.hub_orders            ho   ON ho.hk_orders     = lso.hk_orders
    LEFT JOIN latest_orders                      so   ON so.hk_orders     = ho.hk_orders
    LEFT JOIN dwh_detailed.lnk_orders_users      lou  ON lou.hk_orders    = ho.hk_orders
    WHERE ss.dispatched_date IS NOT NULL
      AND DATE(ss.dispatched_date) = '{d}'
)
INSERT INTO presentation.dm_warehouse_delivery
    (shipment_date, warehouse_id, warehouse_name,
     order_count, total_shipment_qty, avg_processing_time_min,
     delayed_orders_count, unique_customers_count, load_dt)

SELECT
    shipment_date,
    warehouse_id,
    MAX(warehouse_name)                                                   AS warehouse_name,
    COUNT(DISTINCT hk_orders)                                             AS order_count,
    SUM(package_count)                                                    AS total_shipment_qty,
    AVG(processing_time_min)                                              AS avg_processing_time_min,
    COUNT(DISTINCT CASE WHEN is_delayed = 1 THEN hk_orders END)           AS delayed_orders_count,
    COUNT(DISTINCT hk_users)                                              AS unique_customers_count,
    NOW()                                                                 AS load_dt
FROM shipment_facts
GROUP BY shipment_date, warehouse_id
"""

_SQL_DELIVERY_SOURCE = """
SELECT
    DATE(s.dispatched_date) AS shipment_date,
    s.order_external_id::text,
    w.warehouse_code,
    COALESCE(w.warehouse_name, w.warehouse_code) AS warehouse_name,
    COALESCE(s.package_count, 0) AS package_count,
    s.created_date,
    s.dispatched_date
FROM shipments s
JOIN warehouses w
  ON w.warehouse_code = s.origin_warehouse_code
WHERE s.dispatched_date IS NOT NULL
  AND DATE(s.dispatched_date) = %s
"""


def _load_delivery_from_source(sr_conn, report_date: str) -> int:
    with _pg_conn("logistics_service_db") as logistics_conn:
        shipment_rows = _pg_rows(logistics_conn, _SQL_DELIVERY_SOURCE, (report_date,))

    if not shipment_rows:
        return 0

    order_ids = sorted({row[1] for row in shipment_rows if row[1]})
    order_map = {}
    if order_ids:
        with _pg_conn("order_service_db") as order_conn:
            for order_external_id, order_date, user_external_id in _pg_rows(
                order_conn,
                """
                SELECT
                    order_external_id::text,
                    order_date,
                    user_external_id::text
                FROM orders
                WHERE order_external_id::text = ANY(%s)
                """,
                (order_ids,),
            ):
                order_map[order_external_id] = {
                    "order_date": order_date,
                    "user_external_id": user_external_id,
                }

    aggregated = {}
    for (
        shipment_date,
        order_external_id,
        warehouse_code,
        warehouse_name,
        package_count,
        created_date,
        dispatched_date,
    ) in shipment_rows:
        key = (shipment_date, warehouse_code, warehouse_name)
        bucket = aggregated.setdefault(
            key,
            {
                "order_ids": set(),
                "shipment_qty": 0,
                "processing_minutes": [],
                "delayed_order_ids": set(),
                "user_ids": set(),
            },
        )

        if order_external_id:
            bucket["order_ids"].add(order_external_id)

        bucket["shipment_qty"] += package_count or 0

        if (
            order_external_id
            and created_date is not None
            and dispatched_date is not None
            and (dispatched_date - created_date).total_seconds() > 24 * 60 * 60
        ):
            bucket["delayed_order_ids"].add(order_external_id)

        order_info = order_map.get(order_external_id)
        if order_info and order_info["user_external_id"]:
            bucket["user_ids"].add(order_info["user_external_id"])
        if order_info and order_info["order_date"] and dispatched_date is not None:
            bucket["processing_minutes"].append(
                (dispatched_date - order_info["order_date"]).total_seconds() / 60.0
            )

    payload = []
    for (shipment_date, warehouse_code, warehouse_name), bucket in aggregated.items():
        processing_values = bucket["processing_minutes"]
        avg_processing = (
            sum(processing_values) / len(processing_values)
            if processing_values
            else None
        )
        payload.append(
            (
                shipment_date,
                _stable_int(warehouse_code),
                warehouse_name,
                len(bucket["order_ids"]),
                bucket["shipment_qty"],
                avg_processing,
                len(bucket["delayed_order_ids"]),
                len(bucket["user_ids"]),
                datetime.utcnow(),
            )
        )

    _insert_rows_robust(
        sr_conn,
        """
        INSERT INTO presentation.dm_warehouse_delivery
            (shipment_date, warehouse_id, warehouse_name,
             order_count, total_shipment_qty, avg_processing_time_min,
             delayed_orders_count, unique_customers_count, load_dt)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        payload,
        "delivery_source",
    )
    return len(payload)


def refresh_warehouse_delivery(ds: str, **_):
    report_date = (
        datetime.strptime(ds, "%Y-%m-%d") - timedelta(days=1)
    ).strftime("%Y-%m-%d")
    log.info("[delivery] Processing warehouse delivery for: %s", report_date)

    conn = _conn("presentation")
    try:
        _exec(conn,
              f"DELETE FROM dm_warehouse_delivery WHERE shipment_date = '{report_date}'")

        if _use_dwh_for_delivery(conn):
            log.info("[delivery] Building mart from dwh_detailed...")
            _exec(conn, _SQL_DELIVERY.format(d=report_date))
        else:
            log.warning("[delivery] DWH is not fully ready; falling back to source PostgreSQL tables.")
            _load_delivery_from_source(conn, report_date)

        n = _count(conn,
                   f"SELECT COUNT(*) FROM dm_warehouse_delivery "
                   f"WHERE shipment_date = '{report_date}'")
        log.info("[delivery] Done. Rows for %s: %d", report_date, n)
    finally:
        conn.close()


# ── DAG definitions ────────────────────────────────────────────

_DEFAULTS = {
    "owner": "dwh",
    "retries": 0,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

with DAG(
    dag_id="dm_purchase_analytics",
    description="Витрина 1: Аналитика закупок — full refresh daily",
    schedule="0 6 * * *",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args=_DEFAULTS,
    tags=["dwh", "presentation", "hw3"],
) as _dag1:
    PythonOperator(
        task_id="full_refresh",
        python_callable=refresh_purchase_analytics,
    )


with DAG(
    dag_id="dm_warehouse_delivery",
    description="Витрина 2: Доставка по складам — incremental refresh (yesterday)",
    schedule="0 7 * * *",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args=_DEFAULTS,
    tags=["dwh", "presentation", "hw3"],
) as _dag2:
    PythonOperator(
        task_id="incremental_refresh",
        python_callable=refresh_warehouse_delivery,
    )
