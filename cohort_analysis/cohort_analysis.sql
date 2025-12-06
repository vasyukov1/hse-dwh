WITH

first_purchase AS (
    SELECT
        user_external_id,
        DATE_TRUNC('month', MIN(order_date)) AS cohort_month
    FROM orders
    GROUP BY user_external_id
),

cohort_size AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT user_external_id) AS cohort_size
    FROM first_purchase
    GROUP BY cohort_month
    ORDER BY cohort_month
),

user_activity AS (
    SELECT
        o.user_external_id,
        DATE_TRUNC('month', o.order_date) AS activity_month,
        fp.cohort_month,
        EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', o.order_date), fp.cohort_month)) AS period_num,
        o.total_amount
    FROM orders o
    JOIN first_purchase fp ON o.user_external_id = fp.user_external_id
    WHERE o.order_date < fp.cohort_month + INTERVAL '6 months'
),

cohort_activity AS (
    SELECT
        cohort_month,
        period_num,
        COUNT(DISTINCT user_external_id) AS active_users,
        SUM(total_amount) AS period_revenue
    FROM user_activity
    WHERE period_num >= 0
    GROUP BY cohort_month, period_num
),

cohort_pivot AS (
    SELECT
        cs.cohort_month,
        cs.cohort_size,
        MAX(CASE WHEN ca.period_num = 0 THEN ca.active_users ELSE 0 END) AS period_0_active,
        MAX(CASE WHEN ca.period_num = 1 THEN ca.active_users ELSE 0 END) AS period_1_active,
        MAX(CASE WHEN ca.period_num = 2 THEN ca.active_users ELSE 0 END) AS period_2_active,
        MAX(CASE WHEN ca.period_num = 3 THEN ca.active_users ELSE 0 END) AS period_3_active,
        MAX(CASE WHEN ca.period_num = 4 THEN ca.active_users ELSE 0 END) AS period_4_active,
        MAX(CASE WHEN ca.period_num = 5 THEN ca.active_users ELSE 0 END) AS period_5_active
    FROM cohort_size cs
    LEFT JOIN cohort_activity ca ON cs.cohort_month = ca.cohort_month
    GROUP BY cs.cohort_month, cs.cohort_size
),

cohort_revenue AS (
    SELECT
        fp.cohort_month,
        SUM(o.total_amount) AS total_cohort_revenue
    FROM orders o
    JOIN first_purchase fp ON o.user_external_id = fp.user_external_id
    WHERE o.order_date < fp.cohort_month + INTERVAL '6 months'
    GROUP BY fp.cohort_month
)

SELECT
    cp.cohort_month,
    cp.cohort_size,
    ROUND(cp.period_0_active::DECIMAL / cp.cohort_size * 100, 2) AS period_0_pct,
    ROUND(cp.period_1_active::DECIMAL / cp.cohort_size * 100, 2) AS period_1_pct,
    ROUND(cp.period_2_active::DECIMAL / cp.cohort_size * 100, 2) AS period_2_pct,
    ROUND(cp.period_3_active::DECIMAL / cp.cohort_size * 100, 2) AS period_3_pct,
    ROUND(cp.period_4_active::DECIMAL / cp.cohort_size * 100, 2) AS period_4_pct,
    ROUND(cp.period_5_active::DECIMAL / cp.cohort_size * 100, 2) AS period_5_pct,
    cr.total_cohort_revenue,
    ROUND(COALESCE(cr.total_cohort_revenue, 0) / NULLIF(cp.cohort_size, 0), 2) AS avg_revenue_per_customer
FROM cohort_pivot cp
LEFT JOIN cohort_revenue cr ON cp.cohort_month = cr.cohort_month
ORDER BY cp.cohort_month;
