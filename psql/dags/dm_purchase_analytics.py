"""
DAG: dm_purchase_analytics
Витрина 1: «Аналитика закупок»

Стратегия: полный рефреш (TRUNCATE + INSERT) 1 раз в день.
Источник: StarRocks dwh_detailed (Data Vault 2.0 layer).

«Поставщик» = brand из sat_products (маркетплейс-контекст:
бренд выступает в роли поставщика товара).

Схема назначения: presentation.dm_purchase_analytics
"""

import os
import logging
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.python import PythonOperator

log = logging.getLogger(__name__)

# ──────────────────────────────────────────────────────
# DAG defaults
# ──────────────────────────────────────────────────────
default_args = {
    "owner": "airflow",
    "depends_on_past": False,
    "start_date": datetime(2025, 1, 1),
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
}


# ──────────────────────────────────────────────────────
# Helper
# ──────────────────────────────────────────────────────
def _get_connection():
    """Return a pymysql connection to StarRocks."""
    import pymysql

    return pymysql.connect(
        host=os.getenv("STARROCKS_HOST", "starrocks"),
        port=int(os.getenv("STARROCKS_PORT", "9030")),
        user=os.getenv("STARROCKS_USER", "root"),
        password=os.getenv("STARROCKS_PASSWORD", ""),
        charset="utf8mb4",
        connect_timeout=60,
        autocommit=True,
    )


# ──────────────────────────────────────────────────────
# ETL function
# ──────────────────────────────────────────────────────
def etl_purchase_analytics(**context):
    """
    Full refresh of dm_purchase_analytics.
    Steps:
      1. TRUNCATE target table
      2. INSERT aggregated data from dwh_detailed
    """
    conn = _get_connection()
    cursor = conn.cursor()

    try:
        log.info("Step 1: Truncating presentation.dm_purchase_analytics …")
        cursor.execute("TRUNCATE TABLE presentation.dm_purchase_analytics")

        log.info("Step 2: Inserting aggregated purchase data …")
        insert_sql = """
            INSERT INTO presentation.dm_purchase_analytics
                (purchase_date, product_id, product_name, category,
                 supplier_id, supplier_name,
                 purchase_qty, total_purchase_amount, avg_unit_price,
                 load_dt)

            WITH
            -- Latest snapshot of each product (newest load_dt per hk)
            latest_products AS (
                SELECT hk_products, product_name, category, brand
                FROM (
                    SELECT
                        hk_products, product_name, category, brand,
                        ROW_NUMBER() OVER (
                            PARTITION BY hk_products
                            ORDER BY load_dt DESC
                        ) AS rn
                    FROM dwh_detailed.sat_products
                ) t
                WHERE rn = 1
            ),
            -- Latest snapshot of each order
            latest_orders AS (
                SELECT hk_orders, order_date
                FROM (
                    SELECT
                        hk_orders, order_date,
                        ROW_NUMBER() OVER (
                            PARTITION BY hk_orders
                            ORDER BY load_dt DESC
                        ) AS rn
                    FROM dwh_detailed.sat_orders
                ) t
                WHERE rn = 1
            ),
            -- Latest snapshot of each order-item line
            latest_items AS (
                SELECT hk_lnk_order_items, quantity, unit_price, total_price
                FROM (
                    SELECT
                        hk_lnk_order_items,
                        quantity, unit_price, total_price,
                        ROW_NUMBER() OVER (
                            PARTITION BY hk_lnk_order_items
                            ORDER BY load_dt DESC
                        ) AS rn
                    FROM dwh_detailed.sat_order_items
                ) t
                WHERE rn = 1
            )

            SELECT
                DATE(lo.order_date)                                          AS purchase_date,

                -- product_id: stable integer hash of product_sku
                CAST(
                    ABS(CAST(murmur_hash3_32(COALESCE(hp.product_sku, '')) AS BIGINT))
                AS BIGINT)                                                   AS product_id,

                COALESCE(lp.product_name, 'Unknown')                        AS product_name,
                COALESCE(lp.category,     'Unknown')                        AS category,

                -- supplier_id: stable integer hash of brand
                CAST(
                    ABS(CAST(murmur_hash3_32(COALESCE(lp.brand, '')) AS BIGINT))
                AS BIGINT)                                                   AS supplier_id,

                COALESCE(lp.brand, 'Unknown')                               AS supplier_name,

                SUM(COALESCE(CAST(li.quantity   AS DECIMAL(18,2)), 0))      AS purchase_qty,
                SUM(COALESCE(CAST(li.total_price AS DECIMAL(18,2)), 0))     AS total_purchase_amount,
                AVG(COALESCE(CAST(li.unit_price  AS DECIMAL(18,2)), 0))     AS avg_unit_price,

                NOW()                                                        AS load_dt

            FROM dwh_detailed.lnk_order_items   loi

            JOIN dwh_detailed.hub_products  hp  ON loi.hk_products          = hp.hk_products
            LEFT JOIN latest_products       lp  ON hp.hk_products           = lp.hk_products

            JOIN dwh_detailed.hub_orders    ho  ON loi.hk_orders            = ho.hk_orders
            LEFT JOIN latest_orders         lo  ON ho.hk_orders             = lo.hk_orders

            LEFT JOIN latest_items          li  ON loi.hk_lnk_order_items   = li.hk_lnk_order_items

            WHERE lo.order_date IS NOT NULL

            GROUP BY
                DATE(lo.order_date),
                hp.product_sku,
                lp.product_name,
                lp.category,
                lp.brand
        """
        cursor.execute(insert_sql)

        # Report inserted rows
        cursor.execute("SELECT COUNT(*) FROM presentation.dm_purchase_analytics")
        row_count = cursor.fetchone()[0]
        log.info("dm_purchase_analytics refreshed. Total rows: %d", row_count)

    except Exception:
        log.exception("ETL failed for dm_purchase_analytics")
        raise
    finally:
        cursor.close()
        conn.close()


# ──────────────────────────────────────────────────────
# DAG definition
# ──────────────────────────────────────────────────────
with DAG(
    dag_id="dm_purchase_analytics",
    default_args=default_args,
    description="Витрина 1: Аналитика закупок — полный рефреш раз в день",
    schedule_interval="0 6 * * *",   # every day at 06:00 UTC
    catchup=False,
    max_active_runs=1,
    tags=["presentation", "purchases", "full_refresh"],
) as dag:

    refresh = PythonOperator(
        task_id="refresh_purchase_analytics",
        python_callable=etl_purchase_analytics,
        provide_context=True,
    )
