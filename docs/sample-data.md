# Sample Data — Arrow-style Semiconductor Manufacturer

The POC loads a synthetic but realistic **chip-manufacturing** dataset into Unity
Catalog so business users can generate PowerPoint decks and diagrams from it via
Copilot Studio / Foundry / CoWork agents.

- **Catalog:** `arrow_semiconductor`
- **Schema:** `manufacturing`
- **Loader:** [`databricks/sql/01_create_and_load.sql`](../databricks/sql/01_create_and_load.sql) (run by [`scripts/load-sample-data.ps1`](../scripts/load-sample-data.ps1))
- **Grain:** calendar year **2025**, daily/monthly depending on table

> The data is generated with `rand()`, so exact numbers vary per load. The
> shapes, ranges, and relationships below are stable and chart-ready.

---

## Table of contents
- [Tables](#tables)
- [How to query](#how-to-query)
- [Analytics queries & expected results](#analytics-queries--expected-results)
- [Which chart for which slide](#which-chart-for-which-slide)

---

## Tables

| Table | Grain | Rows (approx) | Purpose |
|-------|-------|---------------|---------|
| `fab_production` | day × fab × node | ~3,650 | Daily wafer starts/completions, dies, yield, cycle time |
| `wafer_yield` | month × fab × node | ~120 | Monthly yield rollup vs. node target |
| `defect_analysis` | month × fab × node × defect | ~500 | Defect counts for Pareto analysis |
| `product_sales` | month × region × family × segment | ~1,440 | Revenue, units, ASP, gross margin |
| `inventory` | month × family × region | ~288 | On-hand, days-of-supply, stock status |
| `supply_chain` | supplier | ~12 | Lead time, on-time delivery, risk |

### Key columns
- **`fab_production`**: `production_date`, `fab_id` (FAB-AZ1/TX2/OR3/NM4), `process_node` (3nm…28nm), `product_family`, `wafers_started`, `wafers_completed`, `good_dies`, `total_dies`, `yield_pct`, `cycle_time_days`
- **`wafer_yield`**: `yield_month`, `fab_id`, `process_node`, `avg_yield_pct`, `target_yield_pct`, `yield_vs_target`
- **`defect_analysis`**: `defect_month`, `fab_id`, `process_node`, `defect_category`, `defect_count`, `ppm`, `severity`
- **`product_sales`**: `order_month`, `fiscal_quarter`, `region`, `product_family`, `customer_segment`, `units_sold`, `revenue_usd`, `avg_selling_price`, `gross_margin_pct`
- **`inventory`**: `snapshot_date`, `product_family`, `warehouse_region`, `on_hand_units`, `days_of_supply`, `stock_status`
- **`supply_chain`**: `supplier_name`, `component_type`, `region`, `lead_time_days`, `on_time_delivery_pct`, `quality_score`, `risk_level`

---

## How to query

**In the Databricks SQL editor** (attach the `poc-serverless-2xs` warehouse):
```sql
USE CATALOG arrow_semiconductor;
USE SCHEMA manufacturing;
SELECT * FROM product_sales LIMIT 20;
```

**Via the SQL Statement Execution API** (what APIM calls under the hood):
```bash
curl -X POST "$DBX_HOST/api/2.0/sql/statements" \
  -H "Authorization: Bearer $DBX_TOKEN" -H "Content-Type: application/json" \
  -d '{ "warehouse_id":"<id>", "statement":"SELECT region, SUM(revenue_usd) FROM arrow_semiconductor.manufacturing.product_sales GROUP BY region", "wait_timeout":"30s" }'
```

**Via APIM** (agent-facing — no Databricks token needed): see [api-calls.md](./api-calls.md).

---

## Analytics queries & expected results

All queries live in [`databricks/sql/02_sample_queries.sql`](../databricks/sql/02_sample_queries.sql).

| # | Question | Query returns | Expected shape |
|---|----------|---------------|----------------|
| Q1 | Yield trend by node | month, node, avg_yield_% | 3nm ≈ 70→79 %, 28nm ≈ 95→99 %; all trend **up** across 2025 |
| Q2 | Revenue by region & quarter | quarter, region, $M | APAC highest, then N. America, EMEA, LATAM smallest |
| Q3 | Revenue share by family | family, $M, % of total | FPGA & Automotive MCU dominate (high ASP) |
| Q4 | Defect Pareto | category, count, cumulative % | Particle + Pattern ≈ 55–60 % of defects |
| Q5 | Monthly good dies by fab | month, fab, dies (M) | FAB-TX2 / FAB-NM4 highest volume (mature nodes) |
| Q6 | Gross margin by family | family, margin %, $M | FPGA ≈ 62 %, Memory ≈ 33 % |
| Q7 | Inventory health (latest) | family, region, status | Mix of Healthy / Low / Critical / Excess |
| Q8 | Supplier risk scorecard | supplier, lead time, OTD %, risk | Substrate suppliers = High risk (55–60 day lead) |
| Q9 | Yield vs target (latest) | node, yield %, target %, gap | Most nodes at/above target by year-end |
| Q10 | Executive KPIs | revenue $M, avg yield %, good dies M, high-risk suppliers | Single-row KPI card |

**Example — Q2 (revenue by region), typical output:**

| fiscal_quarter | region | revenue_musd |
|----------------|--------|-------------:|
| FY25-Q1 | APAC | ~18–24 |
| FY25-Q1 | North America | ~15–20 |
| FY25-Q1 | EMEA | ~11–15 |
| FY25-Q1 | LATAM | ~5–8 |

**Example — Q10 (executive KPIs), typical output:**

| total_revenue_musd | avg_yield_pct | total_good_dies_m | high_risk_suppliers |
|-------------------:|--------------:|------------------:|--------------------:|
| ~900–1,100 | ~88–90 | ~4,000–5,000 | 2 |

---

## Which chart for which slide

| Slide idea | Source query | Recommended visual |
|------------|--------------|--------------------|
| "Yield is improving across all nodes" | Q1 | Multi-series **line** |
| "Where our revenue comes from" | Q2 / Q3 | **Clustered bar** + **donut** |
| "Top quality issues to fix" | Q4 | **Pareto** (bar + cumulative line) |
| "Fab output over the year" | Q5 | **Stacked area** |
| "Most profitable product lines" | Q6 | **Bar** with data labels |
| "Inventory risk today" | Q7 | **Heatmap / stacked bar** |
| "Supply-chain risk" | Q8 | **Bubble** chart |
| "Executive summary" | Q10 | **KPI cards** |

These map directly to the visuals an agent produces in a generated `.pptx`.
