-- Creació dataset silver
CREATE SCHEMA `sprint3-analytics-biel-514209.sprint3_silver`
  OPTIONS (
    location = 'EU');
-- CAPA BRONZE
-- Creació taules externes transactions_raw,companies_raw, american_users_raw, european_users_raw, credit_cards_raw

CREATE OR REPLACE EXTERNAL TABLE `sprint3-analytics-biel-514209.sprint3_bronze.transactions_raw`
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/ERP/transactions.csv'],
  field_delimiter = ';',
  skip_leading_rows = 1
);

CREATE OR REPLACE EXTERNAL TABLE `sprint3-analytics-biel-514209.sprint3_bronze.companies_raw`
(
  company_id STRING,
  company_name STRING,
  phone STRING,
  email STRING,
  country STRING,
  website STRING
)
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/ERP/companies.csv'],
  skip_leading_rows = 1
);

CREATE OR REPLACE EXTERNAL TABLE `sprint3-analytics-biel-514209.sprint3_bronze.american_users_raw`
OPTIONS (
  format='csv',
  uris = ['gs://bootcamp-data-analytics-public/CRM/american_users.csv'],
  skip_leading_rows = 1
);

CREATE OR REPLACE EXTERNAL TABLE `sprint3-analytics-biel-514209.sprint3_bronze.european_users_raw`
OPTIONS (
  format='csv',
  uris = ['gs://bootcamp-data-analytics-public/CRM/european_users.csv'],
  skip_leading_rows = 1
);

CREATE OR REPLACE EXTERNAL TABLE `sprint3-analytics-biel-514209.sprint3_bronze.credit_cards_raw`
OPTIONS (
  format='csv',
  uris = ['gs://bootcamp-data-analytics-public/CRM/credit_cards.csv'],
  skip_leading_rows = 1
);

-- Creació taula transactions_raw_native i comprobacions de costos:


CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_bronze.transactions_raw_native`
AS
SELECT * 
FROM `sprint3-analytics-biel-514209.sprint3_bronze.transactions_raw` ;


SELECT id
FROM `sprint3_bronze.transactions_raw`;


SELECT id
FROM `sprint3_bronze.transactions_raw_native`;

SELECT *
FROM `sprint3-analytics-biel-514209.sprint3_bronze.transactions_raw`;

SELECT *
FROM `sprint3-analytics-biel-514209.sprint3_bronze.transactions_raw`
LIMIT 10;

SELECT *
FROM `sprint3_bronze.transactions_raw_native`;

-- Consulta: 5 dies amb més ingressos de l'any
SELECT SUBSTR(CAST(timestamp AS STRING),1,10) AS dia, ROUND(SUM(amount),2) AS ingressos
FROM `sprint3_bronze.transactions_raw_native`
WHERE declined = 0
AND SUBSTR(CAST(timestamp AS STRING),1,4) = "2021"
GROUP BY SUBSTR(CAST(timestamp AS STRING),1,10)
ORDER BY ingressos DESC
LIMIT 5;

-- Consulta: Llista el nom, país i data de les transaccions realitzades per empreses que van fer 
--           operacions entre 100 i 200 euros en alguna d'aquestes dates: 29-04-2015, 20-07-2018 o 13-03-2024.

SELECT company_name, country, SUBSTR(CAST(timestamp AS STRING),1,10) AS dia
FROM `sprint3_bronze.transactions_raw_native` AS t
JOIN `sprint3_bronze.companies_raw` AS c
ON t.business_id=c.company_id
WHERE SUBSTR(CAST(timestamp AS STRING),1,10) IN ("2015-04-29","2018-07-20","2024-03-13")
AND amount BETWEEN 100 AND 200;

-- CAPA SILVER

-- Creació taula products_clean
CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_silver.products_clean`
AS
SELECT
  id AS product_id,
  product_name AS name,
  CAST(REGEXP_REPLACE(CAST(price AS STRING), r'[^0-9.]', '') AS FLOAT64)
    AS price,
  colour,
  weight,
  CAST(REPLACE(CAST(warehouse_id AS STRING), 'WH-', '') AS INT64)
    AS warehouse_id,
  category,
  brand,
  cost,
  launch_date
  
FROM `sprint3-analytics-biel-514209.sprint3_bronze.products_raw`;

-- Creació taula transactions_clean

CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_silver.transactions_clean` AS
SELECT 
  id AS transaction_id,
  
  card_id,
  business_id,
  
  timestamp,
  
  IFNULL(SAFE_CAST(amount AS FLOAT64), 0.0) AS amount,
  
  declined,
  
  ARRAY(
    SELECT SAFE_CAST(TRIM(p) AS INT64)
    FROM UNNEST(SPLIT(product_ids, ',')) AS p
    WHERE TRIM(p) != ''
  ) AS product_ids,
  
  user_id,
  
  SAFE_CAST(lat AS FLOAT64) AS lat,
  SAFE_CAST(longitude AS FLOAT64) AS longitude

FROM 
  `sprint3-analytics-biel-514209.sprint3_bronze.transactions_raw`;
  
-- Unificació d'usuaris

CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_silver.users_combined` AS
SELECT 
  id AS user_id,
  name,
  surname,
  phone,
  email,
  birth_date,
  country,
  city,
  postal_code,
  address,
  'America' AS origin
FROM 
  `sprint3-analytics-biel-514209.sprint3_bronze.american_users_raw`

UNION ALL

SELECT 
  id AS user_id,
  name,
  surname,
  phone,
  email,
  birth_date,
  country,
  city,
  postal_code,
  address,
  'Europe' AS origin
FROM 
  `sprint3-analytics-biel-514209.sprint3_bronze.european_users_raw`;
  
-- Creació companies_clean i credit_card_clean

CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_silver.companies_clean` AS
SELECT 
  company_id,
  company_name,
  phone,
  email,
  country,
  website
FROM 
  `sprint3-analytics-biel-514209.sprint3_bronze.companies_raw`;

CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_silver.credit_cards_clean` AS
SELECT 
  id AS credit_card_id,
  user_id,
  iban,
  pan,
  pin,
  cvv,
  track1,
  track2,
  expiring_date
FROM 
  `sprint3-analytics-biel-514209.sprint3_bronze.credit_cards_raw`;
-- CAPA GOLD
-- Vista marketing

CREATE OR REPLACE VIEW `sprint3-analytics-biel-514209.sprint3_gold.v_marketing_kpis` AS
SELECT company_name,phone, country, ROUND(AVG(amount),2) AS mitjana_compra,
        CASE WHEN AVG(amount)>260 THEN 'Premium'
        ELSE 'Standard'
        END AS client_tier
FROM `sprint3-analytics-biel-514209.sprint3_silver.companies_clean` c
LEFT JOIN `sprint3-analytics-biel-514209.sprint3_silver.transactions_clean` t
  ON c.company_id = t.business_id

GROUP BY 
  c.company_id, 
  c.company_name, 
  c.phone, 
  c.country;

  SELECT *
  FROM `sprint3_gold.v_marketing_kpis`
  ORDER BY mitjana_compra DESC;

-- Ranking productes

CREATE OR REPLACE TABLE `sprint3-analytics-biel-514209.sprint3_gold.product_sales_ranking` AS
SELECT 
  p.product_id,
  p.name,
  p.price,
  p.colour,
  COUNT(t.transaction_id) AS total_sold
FROM 
  `sprint3-analytics-biel-514209.sprint3_silver.products_clean` p
LEFT JOIN 
  `sprint3-analytics-biel-514209.sprint3_silver.transactions_clean` t
  ON p.product_id IN UNNEST(t.product_ids)
GROUP BY 
  p.product_id, 
  p.name, 
  p.price, 
  p.colour;

-- Exportació resultats

EXPORT DATA OPTIONS(
  uri='gs://sprint3-bucket-biel/product_sales_ranking*.csv',
  format='CSV',
  overwrite=true,
  header=true
) AS
SELECT 
  product_id,
  name,
  price,
  colour,
  total_sold
FROM 
  `sprint3-analytics-biel-514209.sprint3_gold.product_sales_ranking`
ORDER BY 
  total_sold DESC;