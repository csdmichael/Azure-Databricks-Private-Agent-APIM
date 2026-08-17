-- =====================================================================
--  Arrow-style Semiconductor POC -- Sample Analytics Queries
--  Each query is tuned to produce a specific PowerPoint-ready visual.
--  Run in the Databricks SQL editor, or call via the SQL Statement
--  Execution API / APIM (see docs/api-calls.md).
-- =====================================================================

-- Q1. Monthly yield trend by process node  ->  LINE CHART
--     (X = month, Y = avg yield %, series = node). Shows ramp/maturity.
SELECT
  yield_month,
  process_node,
  ROUND(AVG(avg_yield_pct) * 100, 2) AS avg_yield_pct
FROM databricks_ws_ai_poc.arrow_semiconductor.wafer_yield
GROUP BY yield_month, process_node
ORDER BY yield_month, process_node;

-- Q2. Revenue by region and quarter  ->  STACKED / CLUSTERED BAR
SELECT
  fiscal_quarter,
  region,
  ROUND(SUM(revenue_usd) / 1e6, 2) AS revenue_musd
FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales
GROUP BY fiscal_quarter, region
ORDER BY fiscal_quarter, region;

-- Q3. Revenue share by product family  ->  PIE / DONUT
SELECT
  product_family,
  ROUND(SUM(revenue_usd) / 1e6, 2) AS revenue_musd,
  ROUND(100 * SUM(revenue_usd) / SUM(SUM(revenue_usd)) OVER (), 1) AS pct_of_total
FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales
GROUP BY product_family
ORDER BY revenue_musd DESC;

-- Q4. Defect Pareto (top categories, full year)  ->  PARETO (bar + cumulative %)
SELECT
  defect_category,
  SUM(defect_count) AS total_defects,
  ROUND(100 * SUM(defect_count) / SUM(SUM(defect_count)) OVER (), 1) AS pct,
  ROUND(100 * SUM(SUM(defect_count)) OVER (ORDER BY SUM(defect_count) DESC)
            / SUM(SUM(defect_count)) OVER (), 1) AS cumulative_pct
FROM databricks_ws_ai_poc.arrow_semiconductor.defect_analysis
GROUP BY defect_category
ORDER BY total_defects DESC;

-- Q5. Monthly production volume (good dies) by fab  ->  AREA / COLUMN
SELECT
  trunc(production_date, 'MM') AS production_month,
  fab_id,
  CAST(SUM(good_dies) / 1e6 AS DECIMAL(10,2)) AS good_dies_millions
FROM databricks_ws_ai_poc.arrow_semiconductor.fab_production
GROUP BY trunc(production_date, 'MM'), fab_id
ORDER BY production_month, fab_id;

-- Q6. Gross margin by product family  ->  BAR (with data labels)
SELECT
  product_family,
  ROUND(AVG(gross_margin_pct) * 100, 1) AS avg_gross_margin_pct,
  ROUND(SUM(revenue_usd) / 1e6, 2)      AS revenue_musd
FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales
GROUP BY product_family
ORDER BY avg_gross_margin_pct DESC;

-- Q7. Inventory health snapshot (latest month)  ->  STACKED BAR / HEATMAP
SELECT
  product_family,
  warehouse_region,
  stock_status,
  on_hand_units,
  days_of_supply
FROM databricks_ws_ai_poc.arrow_semiconductor.inventory
WHERE snapshot_date = (SELECT MAX(snapshot_date) FROM databricks_ws_ai_poc.arrow_semiconductor.inventory)
ORDER BY product_family, warehouse_region;

-- Q8. Supplier risk scorecard  ->  BUBBLE / TABLE
--     (X = lead_time_days, Y = on_time_delivery_pct, size = quality_score, color = risk)
SELECT
  supplier_name,
  component_type,
  region,
  lead_time_days,
  on_time_delivery_pct,
  quality_score,
  risk_level
FROM databricks_ws_ai_poc.arrow_semiconductor.supply_chain
ORDER BY risk_level DESC, lead_time_days DESC;

-- Q9. Yield vs target by node (latest month)  ->  BULLET / DIVERGING BAR
SELECT
  process_node,
  ROUND(AVG(avg_yield_pct) * 100, 2)   AS avg_yield_pct,
  ROUND(AVG(target_yield_pct) * 100, 2) AS target_yield_pct,
  ROUND(AVG(yield_vs_target) * 100, 2)  AS gap_pct
FROM databricks_ws_ai_poc.arrow_semiconductor.wafer_yield
WHERE yield_month = (SELECT MAX(yield_month) FROM databricks_ws_ai_poc.arrow_semiconductor.wafer_yield)
GROUP BY process_node
ORDER BY process_node;

-- Q10. Executive KPI headline (single slide summary)  ->  KPI CARDS
SELECT
  (SELECT ROUND(SUM(revenue_usd)/1e6, 1) FROM databricks_ws_ai_poc.arrow_semiconductor.product_sales) AS total_revenue_musd,
  (SELECT ROUND(AVG(yield_pct)*100, 1)   FROM databricks_ws_ai_poc.arrow_semiconductor.fab_production) AS avg_yield_pct,
  (SELECT CAST(SUM(good_dies)/1e6 AS DECIMAL(10,1)) FROM databricks_ws_ai_poc.arrow_semiconductor.fab_production) AS total_good_dies_millions,
  (SELECT COUNT(*) FROM databricks_ws_ai_poc.arrow_semiconductor.supply_chain WHERE risk_level = 'High') AS high_risk_suppliers;
