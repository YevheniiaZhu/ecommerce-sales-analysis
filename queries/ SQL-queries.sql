DELETE FROM ecommerce_dataset
WHERE 
    order_id IS NULL 
    OR user_id IS NULL 
    OR order_date IS NULL;

SELECT COUNT(*) FROM ecommerce_dataset;
-- Оновити вихідний рядок даних з дублікатами (якщо вихідне значення дорівнює NULL)
UPDATE ecommerce_dataset AS T1
SET 
    category = COALESCE(T1.category, T2.category),
    payment_method = COALESCE(T1.payment_method, T2.payment_method),
    delivery_status = COALESCE(T1.delivery_status, T2.delivery_status),
    total = COALESCE(T1.total, T2.total)
FROM 
    ecommerce_dataset AS T2
WHERE 
    -- 1. Співставлення рядків з однаковим ID замовлення
    T1.order_id = T2.order_id 
    -- 2. Вибір оригінального рядка (з меншим ROWID) для оновлення
    AND T1.ROWID = (SELECT MIN(ROWID) FROM ecommerce_dataset WHERE order_id = T1.order_id)
    -- 3. Вибір дубліката (з більшим ROWID) як джерела даних
    AND T2.ROWID = (SELECT MAX(ROWID) FROM ecommerce_dataset WHERE order_id = T2.order_id);

COMMIT;

-- Видаляємо всі, окрім найстарішого (найменшого ROWID) запису
DELETE FROM ecommerce_dataset
WHERE ROWID NOT IN (
    SELECT MIN(ROWID)
    FROM ecommerce_dataset
    GROUP BY order_id
);

COMMIT;


SELECT COUNT(*) FROM ecommerce_dataset;


WITH categ_country_stat AS (
SELECT 
category,
country,
COUNT(order_id) AS total_orders,
SUM(CASE WHEN delivery_status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled_orders,
SUM(CASE WHEN delivery_status = 'Returned' THEN 1 ELSE 0 END) AS returned_orders,
SUM(CASE WHEN delivery_status = 'Pending' THEN 1 ELSE 0 END) AS pending_orders
FROM ecommerce_dataset
GROUP BY
category, country
)
SELECT 
category,
country,
total_orders,
ROUND(CAST(cancelled_orders AS REAL) * 100 / total_orders, 2) AS cancelled_percent,
ROUND(CAST(returned_orders AS REAL) * 100 / total_orders, 2) AS returned_percent,
ROUND(CAST(pending_orders AS REAL) * 100 / total_orders, 2) AS  pending_percent,
ROUND((CAST(cancelled_orders AS REAL) + CAST(returned_orders AS REAL)) * 100 / total_orders, 2) AS combo_percent
FROM categ_country_stat
WHERE total_orders > 0
ORDER BY
combo_percent DESC,
cancelled_percent DESC,
returned_percent DESC,
pending_percent DESC
LIMIT 20;


WITH categ_country_stat_deliv AS (
SELECT 
category, 
country,
COUNT(order_id) AS total_orders,
SUM(CASE WHEN delivery_status = 'Delivered' THEN 1 ELSE 0 END) AS delivered_orders
FROM ecommerce_dataset
GROUP BY
category, country
)
SELECT 
category,
country,
total_orders,
ROUND(CAST(delivered_orders AS REAL) * 100 / total_orders, 2) AS delivered_percent
FROM categ_country_stat_deliv
WHERE total_orders > 0
ORDER BY
delivered_percent DESC
LIMIT 20;

SELECT 
country,
COUNT(DISTINCT user_id) AS total_users,
COUNT(order_id) AS total_orders,
ROUND(CAST(COUNT(order_id) AS REAL) / COUNT(DISTINCT user_id), 2) AS avg_orders_per_user
FROM ecommerce_dataset 
GROUP BY country 
HAVING COUNT(DISTINCT user_id) > 0 
ORDER BY avg_orders_per_user DESC;

SELECT
country,
COUNT(order_id) AS total_orders,
ROUND(AVG(total), 2) AS avg_total
FROM ecommerce_dataset
GROUP BY country
ORDER BY avg_total DESC
LIMIT 5;

SELECT 
delivery_status AS status,
COUNT(order_id) AS total_orders,
ROUND(AVG(total), 2) AS avg_total,
MIN(total) AS min_total,
MAX(total) AS max_total
FROM ecommerce_dataset
GROUP BY status 
ORDER BY avg_total DESC;

CREATE VIEW ploblem_paym_dev_analys AS
SELECT 
device,
payment_method,
COUNT(order_id) AS total_orders,
ROUND(CAST(SUM(CASE WHEN delivery_status = 'Pending' THEN 1 ELSE 0 END) AS REAL) * 100 / COUNT(order_id), 2) AS pending_percent,
ROUND(CAST(SUM(CASE WHEN delivery_status = 'Cancelled' THEN 1 ELSE 0 END) AS REAL) * 100 / COUNT(order_id), 2) AS cancelled_percent,
ROUND(CAST(SUM(CASE WHEN delivery_status = 'Returned' THEN 1 ELSE 0 END) AS REAL) * 100 / COUNT(order_id), 2) AS returned_percent,
ROUND((CAST(SUM(CASE WHEN delivery_status = 'Cancelled' THEN 1 ELSE 0 END) AS REAL) + CAST(SUM(CASE WHEN delivery_status = 'Returned' 
THEN 1 ELSE 0 END) AS REAL))  * 100 / COUNT(order_id), 2) AS can_ret_percent
FROM ecommerce_dataset
GROUP BY device, payment_method;

SELECT
device,
payment_method,
total_orders, 
pending_percent,
cancelled_percent,
returned_percent,
can_ret_percent
FROM ploblem_paym_dev_analys
WHERE total_orders >= 50
ORDER BY can_ret_percent DESC
LIMIT 10;


CREATE VIEW CustomerRFM AS
SELECT
    user_id,
    -- 1. RECENCY (Нещодавність): Дні з останнього замовлення до кінця 2023 року
    CAST(JULIANDAY('2023-12-31') - JULIANDAY(MAX(order_date)) AS INTEGER) AS recency_days,
    -- 2. FREQUENCY (Частота): Загальна кількість замовлень
    COUNT(order_id) AS frequency_orders,
    -- 3. MONETARY (Грошова цінність): Загальна сума витрат
    ROUND(SUM(total), 2) AS monetary_value
FROM
    ecommerce_dataset
WHERE
    order_id IS NOT NULL 
    AND total IS NOT NULL 
    AND order_date IS NOT NULL 
GROUP BY
    user_id
HAVING
    COUNT(order_id) > 0
ORDER BY
    monetary_value DESC, 
    frequency_orders DESC,
    recency_days ASC;

-- Для перегляду VIP-клієнтів:
SELECT *
FROM CustomerRFM
ORDER BY monetary_value DESC
LIMIT 20; -- Показує топ-20 клієнтів за грошовою цінністю

SELECT
delivery_status,
COUNT(order_id) AS total_orders,
    -- Обчислення середнього відсотка знижки безпосередньо
ROUND(AVG(discount), 2) AS avg_discount
FROM ecommerce_dataset
WHERE
    delivery_status IN ('Delivered', 'Cancelled', 'Returned')
    AND discount IS NOT NULL
GROUP BY delivery_status
ORDER BY avg_discount DESC;
