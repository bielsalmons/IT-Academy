-- Nivell 1
-- Exercici 1
SELECT *
FROM `sprint3_silver.transactions_clean` AS t
JOIN `sprint3_silver.companies_clean` AS c
ON c.company_id=t.business_id
WHERE country="Germany"
AND SUBSTR(CAST(timestamp AS STRING),1, 10)="2022-03-12";

-- Exercici 2 pas 1
CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_silver.transactions_recent` AS
SELECT
  * EXCEPT(timestamp),
  TIMESTAMP_SUB(
    CURRENT_TIMESTAMP(), 
    INTERVAL CAST(RAND() * 50 AS INT64) DAY
  ) AS timestamp
FROM
  `sprint3-analytics-biel-514209.sprint3_silver.transactions_clean`;

-- Exercici 2 pas 2

CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_gold.fact_transactions_optimized`
PARTITION BY DATE(timestamp)
CLUSTER BY business_id
AS
SELECT
  *
FROM
  `sprint3-analytics-biel-514209.sprint3_silver.transactions_recent`;

-- Exercici 3

SELECT *
FROM `sprint3_silver.transactions_recent`
WHERE DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY);

SELECT *
FROM `sprint3_gold.fact_transactions_optimized`
WHERE DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY);

-- Exercici 4

CREATE OR REPLACE MATERIALIZED VIEW `sprint3-analytics-biel-514209.sprint3_gold.mv_daily_sales` AS
(SELECT DATE(timestamp) AS Dia, SUM(amount) AS total_vendes, COUNT(transaction_id) AS total_transaccions
FROM `sprint3_gold.fact_transactions_optimized`
WHERE declined= 0
GROUP BY DATE(timestamp));

SELECT Dia, ROUND(total_vendes,2) AS total_vendes ,total_transaccions
FROM `sprint3-analytics-biel-514209.sprint3_gold.mv_daily_sales`
ORDER BY Dia DESC;

-- Nivell 2
-- Exercici 1


WITH VIP_Stats AS (
  SELECT 
    user_id, 
    ROUND(SUM(amount), 2) AS total_despesa,
    COUNT(transaction_id) AS num_compres,
    ROUND(AVG(amount),2) AS tiquet_mig,
    MAX(amount) AS max_compra
  FROM `sprint3_gold.fact_transactions_optimized`
  WHERE declined = 0
  GROUP BY user_id
  HAVING total_despesa > 500
)
SELECT 
  v.user_id,
  CONCAT(u.name, ' ', u.surname) AS nom_complet,
  u.email,
  v.num_compres,
  v.tiquet_mig,
  v.max_compra,
  v.total_despesa
FROM VIP_Stats AS v
JOIN `sprint3-analytics-biel-514209.sprint3_silver.users_combined` AS u
  ON v.user_id = u.user_id
ORDER BY v.total_despesa DESC;

-- Exercici 2

WITH vendes_amb_ahir AS (
SELECT Dia AS Data, ROUND(total_vendes,2) AS Vendes_Avui,
ROUND(lag(total_vendes) OVER (ORDER BY DIA ASC),2) AS Vendes_Ahir
FROM `sprint3_gold.mv_daily_sales`)

SELECT Data, Vendes_Avui, Vendes_Ahir,
ROUND(SAFE_DIVIDE((Vendes_Avui-Vendes_Ahir), Vendes_Ahir),2)*100 AS Diff_Percentual
FROM vendes_amb_ahir
ORDER BY DATA ASC;

-- Exercici 3

SELECT Dia AS Data,
ROUND(total_vendes, 2) AS Vendes_del_Dia,
ROUND(SUM(total_vendes) OVER (PARTITION BY EXTRACT(YEAR FROM Dia) ORDER BY Dia ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),2) AS Vendes_Acumulades_YTD
FROM
  `sprint3-analytics-biel-514209.sprint3_gold.mv_daily_sales`
ORDER BY
Data ASC;

-- Exercici 4

WITH primerers3_compres AS (
  SELECT 
    user_id, 
    timestamp AS Data_compra, 
    amount AS despesa_compra,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY timestamp ASC) AS num_compra
  FROM `sprint3_gold.fact_transactions_optimized`
  WHERE Declined = 0
  QUALIFY num_compra <= 3
),
mitjana_compra AS (
  SELECT 
    user_id, 
    ROUND(AVG(despesa_compra), 2) AS mitjana_3_compres
  FROM primerers3_compres
  GROUP BY user_id
)
SELECT 
  p.user_id, 
  CONCAT(u.name, ' ', u.surname) AS nom_complet,
  u.email,
  p.Data_compra, 
  ROUND(p.despesa_compra, 2) AS import_3a_compra, 
  m.mitjana_3_compres
FROM primerers3_compres AS p
JOIN mitjana_compra AS m
  USING (user_id)
JOIN `sprint3_silver.users_combined` AS u
  USING (user_id)
WHERE p.num_compra = 3;

-- Nivell 3

-- Exercici 1

CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_gold.dim_transactions_flat` AS
SELECT t.transaction_id, 
DATE(t.timestamp) AS timestamp, 
t.amount AS total_ticket, 
p.product_id AS product_sku, 
p.name AS product_name,
p.price AS product_price
FROM `sprint3_gold.fact_transactions_optimized` AS t
CROSS JOIN UNNEST(t.product_ids) AS single_product_id
JOIN `sprint3_silver.products_clean` AS p
ON single_product_id = p.product_id
WHERE t.declined = 0;

-- Exercici 2

SELECT product_name, COUNT(*) AS N_vendes
FROM `sprint3_gold.dim_transactions_flat`
GROUP BY  product_name
ORDER BY N_vendes DESC
LIMIT 5;

-- Exercici 3

-- Funció persistent
CREATE OR REPLACE FUNCTION `sprint3-analytics-biel-514209.sprint3_gold.calculate_tax`(
amount FLOAT64, tax_rate FLOAT64)
RETURNS FLOAT64
AS (ROUND(amount * (1 + tax_rate), 2));

-- Creació taula

CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_gold.dim_transactions_flat` AS
WITH taula AS (
  SELECT * EXCEPT(product_ids)
  FROM `sprint3_gold.fact_transactions_optimized`
  CROSS JOIN UNNEST(product_ids) AS id_producte
  WHERE declined = 0
)
SELECT 
transaction_id, 
DATE(timestamp) AS Dia, 
amount AS total_ticket, 
p.product_id AS product_sku,
p.name AS product_name, 
p.price AS product_price,
`sprint3-analytics-biel-514209.sprint3_gold.calculate_tax`(p.price, 0.21) AS product_price_tax_inc
FROM taula
JOIN `sprint3-analytics-biel-514209.sprint3_silver.products_clean` AS p
ON taula.id_producte = p.product_id;

SELECT *
FROM `sprint3_gold.dim_transactions_flat`;
