"""
dwh_refresh.py — HW3
DAG 1: dm_purchase_analytics  — full refresh, 06:00 UTC daily
DAG 2: dm_warehouse_delivery  — incremental (yesterday), 07:00 UTC daily
StarRocks via pymysql on port 9031.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta

import pymysql
from airflow import DAG
from airflow.operators.python import PythonOperator

_SR = dict(
    host=os.getenv("STARROCKS_HOST", "starrocks"),
    port=int(os.getenv("STARROCKS_PORT", "9031")),
    user=os.getenv("STARROCKS_USER", "root"),
    password=os.getenv("STARROCKS_PASSWORD", ""),
    charset="utf8mb4",
    connect_timeout=30,
    autocommit=True,
)


def _conn(db: str) -> pymysql.Connection:
    return pymysql.connect(database=db, **_SR)


def _exec(conn, sql: str) -> None:
    with conn.cursor() as cur:
        cur.execute(sql)


def _count(conn, sql: str) -> int:
    with conn.cursor() as cur:
        cur.execute(sql)
        r = cur.fetchone()
        return int(r[0]) if r else 0


# ──────────────────────────────────────────────────────
# Витрина 1: dm_purchase_analytics  (FULL REFRESH)
# purchase_date  = дата заказа
# product_id     = числовой ID товара (hash из hk_products)
# product_name   = название товара
# category       = категория товара
# supplier_id    = числовой ID «поставщика» (= бренд товара)
# supplier_name  = бренд товара
# purchase_qty   = sum(quantity)
# total_purchase_amount = sum(total_price)
# avg_unit_price = avg(unit_price)
# ──────────────────────────────────────────────────────

_SQL_PURCHASE = """
INSERT INTO presentation.dm_purchase_analytics
    (purchase_date, product_id, supplier_id,
     product_name, category, supplier_name,
     purchase_qty, total_purchase_amount, avg_unit_price, load_dt)
SELECT
    DATE(so.order_date),
    ABS(CONV(SUBSTRING(hp.hk_products,  1, 8), 16, 10)),
    ABS(CONV(SUBSTRING(
            MD5(COALESCE(sp.brand, soi.product_brand_snapshot, 'unknown')),
            1, 8), 16, 10)),
    COALESCE(sp.product_name, soi.product_name_snapshot),
    COALESCE(sp.category,     soi.product_category_snapshot, 'unknown'),
    COALESCE(sp.brand,        soi.product_brand_snapshot,    'unknown'),
    SUM(COALESCE(soi.quantity,    0)),
    SUM(COALESCE(soi.total_price, 0)),
    AVG(COALESCE(soi.unit_price,  0)),
    NOW()
FROM dwh_detailed.lnk_order_items     loi
JOIN dwh_detailed.sat_order_items     soi ON soi.hk_lnk_order_items = loi.hk_lnk_order_items
JOIN dwh_detailed.hub_orders          ho  ON ho.hk_orders   = loi.hk_orders
JOIN dwh_detailed.sat_orders          so  ON so.hk_orders   = ho.hk_orders
JOIN dwh_detailed.hub_products        hp  ON hp.hk_products = loi.hk_products
LEFT JOIN dwh_detailed.sat_products   sp  ON sp.hk_products = hp.hk_products
WHERE so.order_date IS NOT NULL
GROUP BY
    DATE(so.order_date),
    hp.hk_products,
    COALESCE(sp.product_name, soi.product_name_snapshot),
    COALESCE(sp.category,     soi.product_category_snapshot, 'unknown'),
    COALESCE(sp.brand,        soi.product_brand_snapshot,    'unknown')
"""


def refresh_purchase_analytics(ds: str, **_):
    conn = _conn("presentation")
    try:
        n_src = _count(conn, "SELECT COUNT(*) FROM dwh_detailed.lnk_order_items")
        print(f"[purchase] lnk_order_items rows: {n_src}")
        if n_src == 0:
            print("[purchase] WARNING: dwh_detailed is empty — load test data first!")

        _exec(conn, "TRUNCATE TABLE presentation.dm_purchase_analytics")
        _exec(conn, _SQL_PURCHASE)
        n = _count(conn, "SELECT COUNT(*) FROM presentation.dm_purchase_analytics")
        print(f"[purchase] Done. Rows inserted: {n} (ds={ds})")
    finally:
        conn.close()


# ──────────────────────────────────────────────────────
# Витрина 2: dm_warehouse_delivery  (INCREMENTAL)
# shipment_date           = дата отгрузки
# warehouse_id            = числовой ID склада
# warehouse_name          = название склада
# order_count             = кол-во заказов
# total_shipment_qty      = объём (cubic cm)
# avg_processing_time_min = среднее время заказ -> отгрузка (мин)
# delayed_orders_count    = кол-во задержанных
# unique_customers_count  = уникальных заказчиков
# ──────────────────────────────────────────────────────

_SQL_DELIVERY = """
INSERT INTO presentation.dm_warehouse_delivery
    (shipment_date, warehouse_id, warehouse_name,
     order_count, total_shipment_qty, avg_processing_time_min,
     delayed_orders_count, unique_customers_count, load_dt)
SELECT
    DATE(ss.dispatched_date),
    ABS(CONV(SUBSTRING(hw.hk_warehouses, 1, 8), 16, 10)),
    MAX(COALESCE(sw.warehouse_name, hw.warehouse_code)),
    COUNT(DISTINCT ho.hk_orders),
    SUM(COALESCE(ss.volume_cubic_cm, 0)),
    AVG(CASE
        WHEN so.order_date IS NOT NULL AND ss.dispatched_date IS NOT NULL
        THEN TIMESTAMPDIFF(MINUTE, so.order_date, ss.dispatched_date)
    END),
    SUM(CASE
        WHEN ss.actual_delivery_date IS NOT NULL
             AND ss.estimated_delivery_date IS NOT NULL
             AND ss.actual_delivery_date > ss.estimated_delivery_date
        THEN 1 ELSE 0
    END),
    COUNT(DISTINCT lou.hk_users),
    NOW()
FROM dwh_detailed.lnk_shipments_warehouses   lsw
JOIN dwh_detailed.hub_warehouses             hw   ON hw.hk_warehouses = lsw.hk_warehouses
JOIN dwh_detailed.hub_shipments              hs   ON hs.hk_shipments  = lsw.hk_shipments
JOIN dwh_detailed.sat_shipments              ss   ON ss.hk_shipments  = hs.hk_shipments
LEFT JOIN dwh_detailed.sat_warehouses        sw   ON sw.hk_warehouses = hw.hk_warehouses
LEFT JOIN dwh_detailed.lnk_shipments_orders  lso  ON lso.hk_shipments = hs.hk_shipments
LEFT JOIN dwh_detailed.hub_orders            ho   ON ho.hk_orders     = lso.hk_orders
LEFT JOIN dwh_detailed.sat_orders            so   ON so.hk_orders     = ho.hk_orders
LEFT JOIN dwh_detailed.lnk_orders_users      lou  ON lou.hk_orders    = ho.hk_orders
WHERE DATE(ss.dispatched_date) = '{d}'
GROUP BY DATE(ss.dispatched_date), hw.hk_warehouses, hw.warehouse_code
"""


def refresh_warehouse_delivery(ds: str, **_):
    report_date = (
        datetime.strptime(ds, "%Y-%m-%d") - timedelta(days=1)
    ).strftime("%Y-%m-%d")

    conn = _conn("presentation")
    try:
        _exec(conn, f"DELETE FROM dm_warehouse_delivery WHERE shipment_date = '{report_date}'")
        _exec(conn, _SQL_DELIVERY.format(d=report_date))
        n = _count(conn, f"SELECT COUNT(*) FROM dm_warehouse_delivery "
                          f"WHERE shipment_date = '{report_date}'")
        print(f"[delivery] Done. Rows for {report_date}: {n}")
    finally:
        conn.close()


# ──────────────────────────────────────────────────────
# DAG definitions
# ──────────────────────────────────────────────────────

_DEFAULTS = {
    "owner": "dwh",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": False,
}

with DAG(
    dag_id="dm_purchase_analytics",
    description="Витрина 1: Аналитика закупок — full refresh",
    schedule="0 6 * * *",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    default_args=_DEFAULTS,
    tags=["dwh", "presentation", "hw3"],
) as _dag1:
    PythonOperator(task_id="full_refresh", python_callable=refresh_purchase_analytics)


with DAG(
    dag_id="dm_warehouse_delivery",
    description="Витрина 2: Доставка по складам — incremental refresh",
    schedule="0 7 * * *",
    start_date=datetime(2025, 1, 1),
    catchup=False,
    default_args=_DEFAULTS,
    tags=["dwh", "presentation", "hw3"],
) as _dag2:
    PythonOperator(task_id="incremental_refresh", python_callable=refresh_warehouse_delivery)
