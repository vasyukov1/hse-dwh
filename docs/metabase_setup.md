# Metabase Setup Guide

## 1. First Launch

Open http://localhost:3000 and complete the setup wizard:
- Language: English / Russian
- Create admin account (e.g. admin@example.com / password)
- Skip "Add your data" for now (we'll add manually)

---

## 2. Connect to StarRocks (MySQL protocol)

Go to **Settings → Admin → Databases → Add database**:

| Field         | Value         |
|---------------|---------------|
| Database type | MySQL         |
| Name          | StarRocks DWH |
| Host          | starrocks     |
| Port          | 9030          |
| Database name | presentation  |
| Username      | root          |
| Password      | (leave empty) |

Click Save. Metabase will sync the tables automatically.

If one of the marts was rebuilt after the first connection and does not appear or looks empty in the UI, run:
- **Admin → Databases → StarRocks DWH → Sync database schema now**
- **Admin → Databases → StarRocks DWH → Re-scan field values now**

---

## 3. Dashboard 1: Аналитика закупок

**Create → New Dashboard → "Аналитика закупок"**

### Chart 1: Динамика закупок по месяцам (Line chart)
```sql
SELECT
    DATE_FORMAT(purchase_date, '%Y-%m') AS month,
    SUM(total_purchase_amount)           AS total_amount
FROM presentation.dm_purchase_analytics
GROUP BY 1
ORDER BY 1
```
Visualization: Line chart, X=month, Y=total_amount

### Chart 2: Топ-5 товаров по объёму закупки (Bar chart)
```sql
SELECT
    product_name,
    SUM(purchase_qty) AS total_qty
FROM presentation.dm_purchase_analytics
GROUP BY product_name
ORDER BY total_qty DESC
LIMIT 5
```
Visualization: Bar chart, X=product_name, Y=total_qty

### Chart 3: Доли категорий в закупках (Pie chart)
```sql
SELECT
    category,
    SUM(total_purchase_amount) AS amount
FROM presentation.dm_purchase_analytics
GROUP BY category
ORDER BY amount DESC
```
Visualization: Pie chart

### Chart 4: Топ-5 поставщиков по объёму (Bar chart)
```sql
SELECT
    supplier_name,
    SUM(total_purchase_amount) AS total_amount
FROM presentation.dm_purchase_analytics
GROUP BY supplier_name
ORDER BY total_amount DESC
LIMIT 5
```
Visualization: Bar chart

### Chart 5: Средняя цена закупки по категориям (Column chart)
```sql
SELECT
    category,
    AVG(avg_unit_price) AS avg_price
FROM presentation.dm_purchase_analytics
GROUP BY category
ORDER BY avg_price DESC
```
Visualization: Bar chart (vertical = column)

---

## 4. Dashboard 2: Доставка по складам

**Create → New Dashboard → "Доставка по складам"**

### Chart 1: Количество заказов по складам за день (Stacked Bar)
```sql
SELECT
    shipment_date,
    warehouse_name,
    order_count
FROM presentation.dm_warehouse_delivery
ORDER BY shipment_date
```
Visualization: Bar chart (stacked), X=shipment_date, series=warehouse_name, Y=order_count

### Chart 2: Динамика времени отгрузки по складам (Line chart)
```sql
SELECT
    shipment_date,
    warehouse_name,
    avg_processing_time_min
FROM presentation.dm_warehouse_delivery
ORDER BY shipment_date
```
Visualization: Line chart, X=shipment_date, series=warehouse_name, Y=avg_processing_time_min

### Chart 3: Доля задержанных заказов на складе (Pie chart)
```sql
SELECT
    warehouse_name,
    SUM(delayed_orders_count) AS delayed
FROM presentation.dm_warehouse_delivery
GROUP BY warehouse_name
```
Visualization: Pie chart

### Chart 4: Объём отгруженной продукции по складам (Column chart)
```sql
SELECT
    warehouse_name,
    SUM(total_shipment_qty) AS total_qty
FROM presentation.dm_warehouse_delivery
GROUP BY warehouse_name
ORDER BY total_qty DESC
```
Visualization: Bar chart (vertical)

### Chart 5: Среднее время выполнения заказа по дням (Line chart)
```sql
SELECT
    shipment_date,
    AVG(avg_processing_time_min) AS avg_min
FROM presentation.dm_warehouse_delivery
GROUP BY shipment_date
ORDER BY shipment_date
```
Visualization: Line chart

### Chart 6: Топ-5 дней с наибольшим количеством уникальных заказчиков (Bar)
```sql
SELECT
    shipment_date,
    SUM(unique_customers_count) AS customers
FROM presentation.dm_warehouse_delivery
GROUP BY shipment_date
ORDER BY customers DESC
LIMIT 5
```
Visualization: Bar chart
