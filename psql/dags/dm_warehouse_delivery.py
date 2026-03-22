"""
DAG: dm_warehouse_delivery
Витрина 2: «Доставка по складам»

Стратегия: инкрементальная (DELETE за бизнес-дату + INSERT).
Бизнес-дата = execution_date - 1 день («обновляем данные за вчера»).
Идемпотентность: при перезапуске старые данные за дату удаляются.

Источник: StarRocks dwh_detailed (Data Vault 2.0 layer).
Схема назначения: presentation.dm_warehouse_delivery
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
def etl_warehouse_delivery(**context):
    """
    Incremental load of dm_warehouse_delivery.
    business_date = DAG execution_date − 1 day.
    Steps:
      1. DELETE rows for business_date (idempotency)
      2. INSERT aggregated data for business_date
    """
    execution_date = context["execution_date"]
    business_date = (execution_date - timedelta(days=1)).strftime("%Y-%m-%d")
    log.info("Processing warehouse delivery for business_date: %s", business_date)

    conn = _get_connection()
    cursor = conn.cursor()

    try:
        # ── Step 1: remove existing rows for this date (idempotency) ──
        log.info("Step 1: Deleting existing rows for %s …", business_date)
        cursor.execute(
            "DELETE FROM presentation.dm_warehouse_delivery "
            f"WHERE shipment_date = '{business_date}'"
        )

        # ── Step 2: insert ──────────────────────────────────────────
        log.info("Step 2: Inserting warehouse delivery data for %s …", business_date)
        insert_sql = f"""
            INSERT INTO presentation.dm_warehouse_delivery
                (shipment_date, warehouse_id, warehouse_name,
                 order_count, total_shipment_qty,
                 avg_processing_time_min, delayed_orders_count,
                 unique_customers_count, load_dt)

            WITH
            -- Latest shipment attributes for the target date
            latest_shipments AS (
                SELECT
                    hk_shipments,
                    package_count,
                    dispatched_date,
                    estimated_delivery_date,
                    actual_delivery_date,
                    created_date
                FROM (
                    SELECT
                        hk_shipments,
                        package_count,
                        dispatched_date,
                        estimated_delivery_date,
                        actual_delivery_date,
                        created_date,
                        ROW_NUMBER() OVER (
                            PARTITION BY hk_shipments
                            ORDER BY load_dt DESC
                        ) AS rn
                    FROM dwh_detailed.sat_shipments
                    WHERE DATE(created_date) = '{business_date}'
                ) t
                WHERE rn = 1
            ),
            -- Latest warehouse attributes
            latest_warehouses AS (
                SELECT hk_warehouses, warehouse_name
                FROM (
                    SELECT
                        hk_warehouses, warehouse_name,
                        ROW_NUMBER() OVER (
                            PARTITION BY hk_warehouses
                            ORDER BY load_dt DESC
                        ) AS rn
                    FROM dwh_detailed.sat_warehouses
                ) t
                WHERE rn = 1
            ),
            -- Latest order attributes (needed for processing-time calc)
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
            )

            SELECT
                DATE(ls.created_date)                                           AS shipment_date,

                -- warehouse_id: stable integer hash of warehouse_code
                CAST(
                    ABS(CAST(murmur_hash3_32(COALESCE(hw.warehouse_code, '')) AS BIGINT))
                AS BIGINT)                                                       AS warehouse_id,

                COALESCE(lw.warehouse_name, hw.warehouse_code)                  AS warehouse_name,

                COUNT(DISTINCT hs.hk_shipments)                                 AS order_count,

                SUM(COALESCE(CAST(ls.package_count AS DECIMAL(18,2)), 0))       AS total_shipment_qty,

                -- avg minutes from order creation to dispatch
                AVG(
                    CASE
                        WHEN ls.dispatched_date IS NOT NULL
                             AND lo.order_date   IS NOT NULL
                        THEN TIMESTAMPDIFF(MINUTE, lo.order_date, ls.dispatched_date)
                        ELSE NULL
                    END
                )                                                                AS avg_processing_time_min,

                -- delayed = actual_delivery_date > estimated_delivery_date
                COUNT(
                    CASE
                        WHEN ls.actual_delivery_date    IS NOT NULL
                             AND ls.estimated_delivery_date IS NOT NULL
                             AND ls.actual_delivery_date > ls.estimated_delivery_date
                        THEN 1
                        ELSE NULL
                    END
                )                                                                AS delayed_orders_count,

                -- unique customers routed through this warehouse on this date
                COUNT(DISTINCT lou.hk_users)                                    AS unique_customers_count,

                NOW()                                                            AS load_dt

            FROM dwh_detailed.hub_shipments                 hs

            -- shipment attributes (filtered to business_date)
            JOIN  latest_shipments                          ls   ON hs.hk_shipments = ls.hk_shipments

            -- warehouse link
            JOIN  dwh_detailed.lnk_shipments_warehouses    lsw  ON hs.hk_shipments   = lsw.hk_shipments
            JOIN  dwh_detailed.hub_warehouses               hw   ON lsw.hk_warehouses = hw.hk_warehouses
            LEFT JOIN latest_warehouses                     lw   ON hw.hk_warehouses  = lw.hk_warehouses

            -- order link (for processing-time + customer count)
            LEFT JOIN dwh_detailed.lnk_shipments_orders     lso  ON hs.hk_shipments = lso.hk_shipments
            LEFT JOIN dwh_detailed.hub_orders               ho   ON lso.hk_orders   = ho.hk_orders
            LEFT JOIN latest_orders                         lo   ON ho.hk_orders    = lo.hk_orders

            -- customer (unique user) count
            LEFT JOIN dwh_detailed.lnk_orders_users         lou  ON ho.hk_orders   = lou.hk_orders

            GROUP BY
                DATE(ls.created_date),
                hw.warehouse_code,
                lw.warehouse_name
        """
        cursor.execute(insert_sql)

        # Report
        cursor.execute(
            "SELECT COUNT(*) FROM presentation.dm_warehouse_delivery "
            f"WHERE shipment_date = '{business_date}'"
        )
        row_count = cursor.fetchone()[0]
        log.info(
            "dm_warehouse_delivery loaded %d rows for %s", row_count, business_date
        )

    except Exception:
        log.exception("ETL failed for dm_warehouse_delivery (date=%s)", business_date)
        raise
    finally:
        cursor.close()
        conn.close()


# ──────────────────────────────────────────────────────
# DAG definition
# ──────────────────────────────────────────────────────
with DAG(
    dag_id="dm_warehouse_delivery",
    default_args=default_args,
    description="Витрина 2: Доставка по складам — инкрементальная загрузка за вчера",
    schedule_interval="0 7 * * *",   # every day at 07:00 UTC (after mart 1)
    catchup=False,
    max_active_runs=1,
    tags=["presentation", "warehouses", "incremental"],
) as dag:

    load = PythonOperator(
        task_id="load_warehouse_delivery",
        python_callable=etl_warehouse_delivery,
        provide_context=True,
    )
