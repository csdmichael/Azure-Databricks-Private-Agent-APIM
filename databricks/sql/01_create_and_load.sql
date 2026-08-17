-- =====================================================================
--  Arrow-style Semiconductor Manufacturer -- Sample Dataset (POC)
--  Target: Databricks SQL (Unity Catalog) on a serverless SQL warehouse.
--  Catalog: databricks_ws_ai_poc (workspace default)   Schema: arrow_semiconductor
--
--  Statements are separated by a line containing exactly: -- @statement
--  (scripts/load-sample-data.ps1 splits on that marker and runs each one
--   via the SQL Statement Execution API).
--  Data is designed to drive PowerPoint visuals: yield trends, revenue by
--  region, defect Pareto, production volumes, inventory health, supplier risk.
-- =====================================================================

-- Account UC uses Default Storage; create a branded SCHEMA inside the workspace
-- default catalog rather than a new catalog (SQL CREATE CATALOG needs a managed location).
CREATE SCHEMA IF NOT EXISTS databricks_ws_ai_poc.arrow_semiconductor
COMMENT 'Semiconductor manufacturing, sales, quality and supply-chain sample data';
-- @statement
-- ------------------------------------------------------------------
-- 1) fab_production : daily wafer production & yield by fab/node
-- ------------------------------------------------------------------
CREATE OR REPLACE TABLE databricks_ws_ai_poc.arrow_semiconductor.fab_production (
  production_date  DATE     COMMENT 'Calendar production day',
  fab_id           STRING   COMMENT 'Fabrication plant identifier',
  fab_location     STRING   COMMENT 'Fab city/state',
  process_node     STRING   COMMENT 'Process technology node (3nm..28nm)',
  product_family   STRING   COMMENT 'Product family produced on the line',
  wafers_started   INT      COMMENT 'Wafers started that day',
  wafers_completed INT      COMMENT 'Wafers completed that day',
  good_dies        INT      COMMENT 'Known-good dies produced',
  total_dies       INT      COMMENT 'Total dies produced',
  yield_pct        DOUBLE   COMMENT 'Die yield (good/total)',
  cycle_time_days  DOUBLE   COMMENT 'Average manufacturing cycle time (days)'
)
COMMENT 'Daily wafer production and yield by fab and process node';
-- @statement
INSERT OVERWRITE databricks_ws_ai_poc.arrow_semiconductor.fab_production
WITH dates AS (
  SELECT explode(sequence(DATE'2025-01-01', DATE'2025-12-31', INTERVAL 1 DAY)) AS d
),
combo AS (
  SELECT * FROM VALUES
    ('FAB-AZ1','Chandler, Arizona','3nm','AI Accelerators',   180, 800, 0.70, 22),
    ('FAB-AZ1','Chandler, Arizona','5nm','Datacenter CPU',    240, 650, 0.78, 18),
    ('FAB-AZ1','Chandler, Arizona','7nm','GPU',               300, 520, 0.85, 15),
    ('FAB-TX2','Austin, Texas','7nm','Automotive MCU',        340, 520, 0.86, 14),
    ('FAB-TX2','Austin, Texas','14nm','Power Management',     420, 360, 0.92, 11),
    ('FAB-TX2','Austin, Texas','28nm','Discrete Power',       500, 210, 0.95, 9),
    ('FAB-OR3','Hillsboro, Oregon','5nm','RF / Wireless',     260, 640, 0.80, 17),
    ('FAB-OR3','Hillsboro, Oregon','7nm','FPGA',              280, 500, 0.84, 16),
    ('FAB-NM4','Rio Rancho, New Mexico','14nm','Memory',      460, 350, 0.90, 12),
    ('FAB-NM4','Rio Rancho, New Mexico','28nm','Analog / Sensors', 520, 200, 0.96, 8)
  AS combo(fab_id, fab_location, process_node, product_family, base_starts, dies_per_wafer, base_yield, base_cycle)
),
base AS (
  SELECT
    d AS production_date,
    fab_id, fab_location, process_node, product_family,
    base_starts, dies_per_wafer, base_yield, base_cycle,
    MONTH(d) AS mo,
    CASE WHEN dayofweek(d) IN (1,7) THEN 0.55 ELSE 1.0 END AS weekday_factor,
    (rand() - 0.5) AS noise
  FROM dates CROSS JOIN combo
),
calc AS (
  SELECT
    production_date, fab_id, fab_location, process_node, product_family,
    CAST(ROUND(base_starts * weekday_factor * (1 + noise*0.18)) AS INT) AS wafers_started,
    dies_per_wafer, base_yield, base_cycle, mo, noise
  FROM base
)
SELECT
  production_date, fab_id, fab_location, process_node, product_family,
  wafers_started,
  CAST(ROUND(wafers_started * (0.96 + rand()*0.03)) AS INT) AS wafers_completed,
  CAST(ROUND(wafers_started * (0.96) * dies_per_wafer *
       LEAST(0.99, GREATEST(0.50, base_yield + (mo-1)*0.008 + noise*0.05))) AS INT) AS good_dies,
  CAST(ROUND(wafers_started * (0.96) * dies_per_wafer) AS INT) AS total_dies,
  ROUND(LEAST(0.99, GREATEST(0.50, base_yield + (mo-1)*0.008 + noise*0.05)), 4) AS yield_pct,
  ROUND(base_cycle + noise*1.5, 1) AS cycle_time_days
FROM calc;
-- @statement
-- ------------------------------------------------------------------
-- 2) wafer_yield : monthly yield rollup by fab/node (curated combos)
-- ------------------------------------------------------------------
CREATE OR REPLACE TABLE databricks_ws_ai_poc.arrow_semiconductor.wafer_yield (
  yield_month     DATE   COMMENT 'First day of the month',
  fab_id          STRING,
  process_node    STRING,
  product_family  STRING,
  wafers_completed INT,
  avg_yield_pct   DOUBLE COMMENT 'Mean die yield for the month',
  best_yield_pct  DOUBLE,
  worst_yield_pct DOUBLE,
  target_yield_pct DOUBLE COMMENT 'Yield target for the node',
  yield_vs_target DOUBLE COMMENT 'avg_yield_pct - target_yield_pct'
)
COMMENT 'Monthly yield rollup with target comparison';
-- @statement
INSERT OVERWRITE databricks_ws_ai_poc.arrow_semiconductor.wafer_yield
SELECT
  trunc(production_date, 'MM')                       AS yield_month,
  fab_id, process_node, product_family,
  CAST(SUM(wafers_completed) AS INT)                 AS wafers_completed,
  ROUND(AVG(yield_pct), 4)                           AS avg_yield_pct,
  ROUND(MAX(yield_pct), 4)                           AS best_yield_pct,
  ROUND(MIN(yield_pct), 4)                           AS worst_yield_pct,
  ROUND(CASE process_node
          WHEN '3nm' THEN 0.75 WHEN '5nm' THEN 0.82 WHEN '7nm' THEN 0.88
          WHEN '14nm' THEN 0.93 ELSE 0.96 END, 4)    AS target_yield_pct,
  ROUND(AVG(yield_pct) - (CASE process_node
          WHEN '3nm' THEN 0.75 WHEN '5nm' THEN 0.82 WHEN '7nm' THEN 0.88
          WHEN '14nm' THEN 0.93 ELSE 0.96 END), 4)   AS yield_vs_target
FROM databricks_ws_ai_poc.arrow_semiconductor.fab_production
GROUP BY trunc(production_date, 'MM'), fab_id, process_node, product_family;
-- @statement
-- ------------------------------------------------------------------
-- 3) defect_analysis : monthly defect Pareto by fab/node/category
-- ------------------------------------------------------------------
CREATE OR REPLACE TABLE databricks_ws_ai_poc.arrow_semiconductor.defect_analysis (
  defect_month    DATE,
  fab_id          STRING,
  process_node    STRING,
  defect_category STRING COMMENT 'Particle, Scratch, Pattern, Etch, Contamination, Overlay, CMP',
  defect_count    INT,
  ppm             DOUBLE COMMENT 'Defects per million dies',
  severity        STRING COMMENT 'Low / Medium / High'
)
COMMENT 'Monthly defect counts for Pareto analysis';
-- @statement
INSERT OVERWRITE databricks_ws_ai_poc.arrow_semiconductor.defect_analysis
WITH months AS (
  SELECT explode(sequence(DATE'2025-01-01', DATE'2025-12-01', INTERVAL 1 MONTH)) AS defect_month
),
fabs AS (
  SELECT * FROM VALUES
    ('FAB-AZ1','3nm'), ('FAB-AZ1','5nm'), ('FAB-TX2','7nm'),
    ('FAB-TX2','14nm'), ('FAB-OR3','5nm'), ('FAB-NM4','28nm')
  AS f(fab_id, process_node)
),
cats AS (
  SELECT * FROM VALUES
    ('Particle', 100), ('Pattern', 78), ('Etch', 60), ('Overlay', 45),
    ('Contamination', 34), ('Scratch', 22), ('CMP', 15)
  AS c(defect_category, base_weight)
)
SELECT
  defect_month, fab_id, process_node, defect_category,
  CAST(ROUND(base_weight
        * (CASE process_node WHEN '3nm' THEN 1.8 WHEN '5nm' THEN 1.4 WHEN '7nm' THEN 1.1 ELSE 0.8 END)
        * (1 + rand()*0.5)
        * (1 - (MONTH(defect_month)-1)*0.03)) AS INT)               AS defect_count,
  ROUND(base_weight * (1 + rand()*0.5) * 2.5, 1)                    AS ppm,
  CASE WHEN base_weight >= 70 THEN 'High'
       WHEN base_weight >= 34 THEN 'Medium' ELSE 'Low' END          AS severity
FROM months CROSS JOIN fabs CROSS JOIN cats;
-- @statement
-- ------------------------------------------------------------------
-- 4) product_sales : monthly revenue by region/family/segment
-- ------------------------------------------------------------------
CREATE OR REPLACE TABLE databricks_ws_ai_poc.arrow_semiconductor.product_sales (
  order_month      DATE,
  fiscal_quarter   STRING COMMENT 'FY25-Q1..Q4',
  region           STRING COMMENT 'North America, EMEA, APAC, LATAM',
  product_family   STRING,
  customer_segment STRING COMMENT 'Automotive, Industrial, Consumer, Datacenter, Aerospace',
  units_sold       INT,
  revenue_usd      DOUBLE,
  avg_selling_price DOUBLE,
  gross_margin_pct DOUBLE
)
COMMENT 'Monthly product revenue for region/family/segment breakdowns';
-- @statement
INSERT OVERWRITE databricks_ws_ai_poc.arrow_semiconductor.product_sales
WITH months AS (
  SELECT explode(sequence(DATE'2025-01-01', DATE'2025-12-01', INTERVAL 1 MONTH)) AS order_month
),
regions AS (
  SELECT * FROM VALUES
    ('North America', 1.00), ('EMEA', 0.72), ('APAC', 1.25), ('LATAM', 0.35)
  AS r(region, region_factor)
),
families AS (
  SELECT * FROM VALUES
    ('Automotive MCU', 14.50, 0.42), ('Power Management', 3.20, 0.48),
    ('RF / Wireless', 6.80, 0.51), ('Memory', 2.10, 0.33),
    ('Analog / Sensors', 1.85, 0.55), ('FPGA', 48.00, 0.62)
  AS f(product_family, asp, margin)
),
segments AS (
  SELECT * FROM VALUES
    ('Automotive', 1.30), ('Industrial', 1.00), ('Consumer', 0.80),
    ('Datacenter', 1.55), ('Aerospace', 0.65)
  AS s(customer_segment, seg_factor)
)
SELECT
  order_month,
  concat('FY25-Q', CAST(quarter(order_month) AS STRING))            AS fiscal_quarter,
  region, product_family, customer_segment,
  CAST(ROUND(12000 * region_factor * seg_factor
        * (1 + (MONTH(order_month)-1)*0.02) * (1 + rand()*0.4)) AS INT) AS units_sold,
  ROUND(12000 * region_factor * seg_factor
        * (1 + (MONTH(order_month)-1)*0.02) * (1 + rand()*0.4)
        * asp * (1 + rand()*0.1), 2)                                 AS revenue_usd,
  ROUND(asp * (1 + rand()*0.1), 2)                                   AS avg_selling_price,
  ROUND(margin * (1 + (rand()-0.5)*0.08), 4)                         AS gross_margin_pct
FROM months CROSS JOIN regions CROSS JOIN families CROSS JOIN segments;
-- @statement
-- ------------------------------------------------------------------
-- 5) inventory : monthly component inventory health
-- ------------------------------------------------------------------
CREATE OR REPLACE TABLE databricks_ws_ai_poc.arrow_semiconductor.inventory (
  snapshot_date   DATE,
  product_family  STRING,
  warehouse_region STRING,
  on_hand_units   INT,
  reserved_units  INT,
  reorder_point   INT,
  days_of_supply  DOUBLE,
  stock_status    STRING COMMENT 'Healthy / Low / Critical / Excess'
)
COMMENT 'Monthly inventory snapshot with stock-health status';
-- @statement
INSERT OVERWRITE databricks_ws_ai_poc.arrow_semiconductor.inventory
WITH months AS (
  SELECT explode(sequence(DATE'2025-01-01', DATE'2025-12-01', INTERVAL 1 MONTH)) AS snapshot_date
),
families AS (
  SELECT * FROM VALUES
    ('Automotive MCU'), ('Power Management'), ('RF / Wireless'),
    ('Memory'), ('Analog / Sensors'), ('FPGA')
  AS f(product_family)
),
regions AS (
  SELECT * FROM VALUES ('North America'),('EMEA'),('APAC'),('LATAM') AS r(warehouse_region)
),
calc AS (
  SELECT
    snapshot_date, product_family, warehouse_region,
    CAST(ROUND(50000 * (0.4 + rand()*1.4)) AS INT)  AS on_hand_units,
    CAST(ROUND(50000 * 0.35 * (0.5 + rand())) AS INT) AS reserved_units,
    30000                                            AS reorder_point,
    ROUND(15 + rand()*70, 1)                         AS days_of_supply
  FROM months CROSS JOIN families CROSS JOIN regions
)
SELECT
  snapshot_date, product_family, warehouse_region,
  on_hand_units, reserved_units, reorder_point, days_of_supply,
  CASE
    WHEN days_of_supply < 20 THEN 'Critical'
    WHEN on_hand_units < reorder_point THEN 'Low'
    WHEN days_of_supply > 70 THEN 'Excess'
    ELSE 'Healthy' END AS stock_status
FROM calc;
-- @statement
-- ------------------------------------------------------------------
-- 6) supply_chain : supplier lead time / on-time delivery / risk
-- ------------------------------------------------------------------
CREATE OR REPLACE TABLE databricks_ws_ai_poc.arrow_semiconductor.supply_chain (
  supplier_name    STRING,
  component_type   STRING COMMENT 'Silicon Wafer, Substrate, Lead Frame, Bond Wire, Chemicals, Photomask',
  region           STRING,
  lead_time_days   INT,
  on_time_delivery_pct DOUBLE,
  quality_score    DOUBLE COMMENT '0-100 supplier quality score',
  risk_level       STRING COMMENT 'Low / Medium / High'
)
COMMENT 'Current supplier scorecard for supply-chain risk views';
-- @statement
INSERT OVERWRITE databricks_ws_ai_poc.arrow_semiconductor.supply_chain
WITH suppliers AS (
  SELECT * FROM VALUES
    ('ShinEtsu Silicon','Silicon Wafer','APAC', 42),
    ('SUMCO Wafers','Silicon Wafer','APAC', 45),
    ('Ibiden Substrates','Substrate','APAC', 60),
    ('AT&S','Substrate','EMEA', 55),
    ('Kyocera','Lead Frame','APAC', 38),
    ('Heraeus','Bond Wire','EMEA', 30),
    ('BASF Electronic','Chemicals','EMEA', 21),
    ('Merck EMD','Chemicals','North America', 25),
    ('Photronics','Photomask','North America', 33),
    ('Toppan Photomask','Photomask','APAC', 40),
    ('Applied Signal','Lead Frame','North America', 28),
    ('DuPont Electronics','Chemicals','North America', 24)
  AS s(supplier_name, component_type, region, lead_time_days)
)
SELECT
  supplier_name, component_type, region, lead_time_days,
  ROUND(88 + rand()*11, 1)                              AS on_time_delivery_pct,
  ROUND(80 + rand()*19, 1)                              AS quality_score,
  CASE
    WHEN lead_time_days >= 55 THEN 'High'
    WHEN lead_time_days >= 35 THEN 'Medium'
    ELSE 'Low' END                                      AS risk_level
FROM suppliers;
-- @statement
-- ------------------------------------------------------------------
-- Validation summary (row counts) -- returned to the loader for logging
-- ------------------------------------------------------------------
SELECT 'fab_production' AS table_name, COUNT(*) AS rows FROM databricks_ws_ai_poc.arrow_semiconductor.fab_production
UNION ALL SELECT 'wafer_yield',    COUNT(*) FROM databricks_ws_ai_poc.arrow_semiconductor.wafer_yield
UNION ALL SELECT 'defect_analysis',COUNT(*) FROM databricks_ws_ai_poc.arrow_semiconductor.defect_analysis
UNION ALL SELECT 'product_sales',  COUNT(*) FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales
UNION ALL SELECT 'inventory',      COUNT(*) FROM databricks_ws_ai_poc.arrow_semiconductor.inventory
UNION ALL SELECT 'supply_chain',   COUNT(*) FROM databricks_ws_ai_poc.arrow_semiconductor.supply_chain
ORDER BY table_name;
