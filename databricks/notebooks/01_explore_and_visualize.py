# Databricks notebook source
# MAGIC %md
# MAGIC # Arrow-style Semiconductor POC — Data & Visualizations
# MAGIC
# MAGIC This notebook explores the `databricks_ws_ai_poc.arrow_semiconductor` sample dataset and
# MAGIC renders the charts that Copilot Studio / Foundry agents reproduce in PowerPoint.
# MAGIC
# MAGIC **Prerequisite:** run `databricks/sql/01_create_and_load.sql` first
# MAGIC (via `scripts/load-sample-data.ps1` or by pasting it into the SQL editor).
# MAGIC
# MAGIC Use the chart controls under each `display()` to switch visual types.

# COMMAND ----------

CATALOG = "databricks_ws_ai_poc"
SCHEMA = "arrow_semiconductor"
spark.sql(f"USE CATALOG {CATALOG}")
spark.sql(f"USE SCHEMA {SCHEMA}")
print(f"Using {CATALOG}.{SCHEMA}")
display(spark.sql("SHOW TABLES"))

# COMMAND ----------

# MAGIC %md ## 1. Yield trend by process node (line chart)

# COMMAND ----------

display(spark.sql("""
  SELECT yield_month, process_node, ROUND(AVG(avg_yield_pct)*100,2) AS avg_yield_pct
  FROM wafer_yield GROUP BY yield_month, process_node ORDER BY yield_month
"""))

# COMMAND ----------

# MAGIC %md ## 2. Revenue by region & quarter (bar chart)

# COMMAND ----------

display(spark.sql("""
  SELECT fiscal_quarter, region, ROUND(SUM(revenue_usd)/1e6,2) AS revenue_musd
  FROM product_sales GROUP BY fiscal_quarter, region ORDER BY fiscal_quarter, region
"""))

# COMMAND ----------

# MAGIC %md ## 3. Revenue share by product family (pie / donut)

# COMMAND ----------

display(spark.sql("""
  SELECT product_family, ROUND(SUM(revenue_usd)/1e6,2) AS revenue_musd
  FROM product_sales GROUP BY product_family ORDER BY revenue_musd DESC
"""))

# COMMAND ----------

# MAGIC %md ## 4. Defect Pareto (bar + cumulative %)

# COMMAND ----------

display(spark.sql("""
  SELECT defect_category, SUM(defect_count) AS total_defects,
         ROUND(100*SUM(SUM(defect_count)) OVER (ORDER BY SUM(defect_count) DESC)
               / SUM(SUM(defect_count)) OVER (),1) AS cumulative_pct
  FROM defect_analysis GROUP BY defect_category ORDER BY total_defects DESC
"""))

# COMMAND ----------

# MAGIC %md ## 5. Monthly good-die production by fab (area / column)

# COMMAND ----------

display(spark.sql("""
  SELECT trunc(production_date,'MM') AS production_month, fab_id,
         CAST(SUM(good_dies)/1e6 AS DECIMAL(10,2)) AS good_dies_millions
  FROM fab_production GROUP BY trunc(production_date,'MM'), fab_id
  ORDER BY production_month, fab_id
"""))

# COMMAND ----------

# MAGIC %md ## 6. Supplier risk scorecard (bubble / table)

# COMMAND ----------

display(spark.sql("SELECT * FROM supply_chain ORDER BY risk_level DESC, lead_time_days DESC"))

# COMMAND ----------

# MAGIC %md
# MAGIC ### Executive KPIs (single-slide summary)

# COMMAND ----------

display(spark.sql("""
  SELECT
    (SELECT ROUND(SUM(revenue_usd)/1e6,1) FROM product_sales) AS total_revenue_musd,
    (SELECT ROUND(AVG(yield_pct)*100,1)  FROM fab_production) AS avg_yield_pct,
    (SELECT CAST(SUM(good_dies)/1e6 AS DECIMAL(10,1)) FROM fab_production) AS total_good_dies_m,
    (SELECT COUNT(*) FROM supply_chain WHERE risk_level='High') AS high_risk_suppliers
"""))
