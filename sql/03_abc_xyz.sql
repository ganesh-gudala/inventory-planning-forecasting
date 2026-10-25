/* =====================================================================
   03 · ABC-XYZ classification
   ABC = value:        sort SKUs by net sales value (last 52 weeks); A = first 80% of value, B = next 15%, C = last 5%
   XYZ = variability:  CV = standard deviation / average of weekly demand (last 52 weeks)
                       X = CV <= 0.75 (steady), Y = 0.75-1.25 (variable), Z = above 1.25 (erratic)
   Builds sku_abc_xyz, which the forecast and policy files use.
   ===================================================================== */

-- AB1: What are each SKU's average weekly demand, variability (CV), price and class? (builds sku_abc_xyz)
DROP TABLE IF EXISTS sku_abc_xyz;
CREATE TABLE sku_abc_xyz AS
WITH stats AS (
    SELECT stock_code,
           SUM(CASE WHEN week_no >= 52 THEN net_value    ELSE 0 END)                        AS net_value_52w,
           SUM(CASE WHEN week_no >= 52 THEN sales_value  ELSE 0 END)                        AS sales_value_52w,
           SUM(CASE WHEN week_no >= 52 THEN units_sold   ELSE 0 END)                        AS units_sold_52w,
           SUM(CASE WHEN week_no >= 52 THEN demand_units ELSE 0 END)                        AS units_52w,
           AVG(CASE WHEN week_no >= 52 THEN demand_units END)                               AS avg_weekly_52w,
           STDDEV_SAMP(CASE WHEN week_no >= 52 THEN demand_units END)                       AS sd_weekly_52w,
           AVG(CASE WHEN week_no BETWEEN 40 AND 52 THEN demand_units END)
             / AVG(CASE WHEN week_no <= 91 THEN demand_units END)                           AS peak_uplift
    FROM weekly_demand
    GROUP BY stock_code
),
ranked AS (
    SELECT s.*,
           sd_weekly_52w / avg_weekly_52w                                                   AS cv,
           sales_value_52w / units_sold_52w                                                 AS avg_price,   -- sale lines only
           SUM(net_value_52w) OVER (ORDER BY net_value_52w DESC ROWS UNBOUNDED PRECEDING)
             / SUM(net_value_52w) OVER ()                                                   AS cum_value_share,
           PERCENT_RANK() OVER (ORDER BY net_value_52w)                                     AS value_percent_rank,
           NTILE(5) OVER (ORDER BY net_value_52w DESC)                                      AS value_quintile
    FROM stats s
)
SELECT stock_code, net_value_52w, units_52w, avg_price, avg_weekly_52w, sd_weekly_52w, cv,
       cum_value_share, value_percent_rank, value_quintile, peak_uplift,
       CASE WHEN peak_uplift >= 1.3 THEN 1 ELSE 0 END                                       AS is_seasonal,
       CASE WHEN cum_value_share <= 0.80 THEN 'A' WHEN cum_value_share <= 0.95 THEN 'B' ELSE 'C' END AS abc,
       CASE WHEN cv <= 0.75 THEN 'X' WHEN cv <= 1.25 THEN 'Y' ELSE 'Z' END                  AS xyz
FROM ranked;

-- AB2: The 9-box matrix: how many SKUs fall in each ABC x XYZ box? (rows = ABC, columns = XYZ)
SELECT abc,
       SUM(CASE WHEN xyz = 'X' THEN 1 ELSE 0 END) AS x_steady,
       SUM(CASE WHEN xyz = 'Y' THEN 1 ELSE 0 END) AS y_variable,
       SUM(CASE WHEN xyz = 'Z' THEN 1 ELSE 0 END) AS z_erratic,
       COUNT(*)                                   AS total_skus
FROM sku_abc_xyz
GROUP BY abc
ORDER BY abc;

-- AB3: The 9-box by value: what share of sales value sits in each box?
SELECT abc,
       ROUND(100 * SUM(CASE WHEN xyz = 'X' THEN net_value_52w ELSE 0 END) / (SELECT SUM(net_value_52w) FROM sku_abc_xyz), 1) AS x_value_pct,
       ROUND(100 * SUM(CASE WHEN xyz = 'Y' THEN net_value_52w ELSE 0 END) / (SELECT SUM(net_value_52w) FROM sku_abc_xyz), 1) AS y_value_pct,
       ROUND(100 * SUM(CASE WHEN xyz = 'Z' THEN net_value_52w ELSE 0 END) / (SELECT SUM(net_value_52w) FROM sku_abc_xyz), 1) AS z_value_pct
FROM sku_abc_xyz
GROUP BY abc
ORDER BY abc;

-- AB4: How concentrated is value (Pareto)? What % of SKUs makes up 50% / 80% / 95% of value?
SELECT ROUND(100.0 * SUM(CASE WHEN cum_value_share <= 0.50 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_skus_for_50pct_value,
       ROUND(100.0 * SUM(CASE WHEN cum_value_share <= 0.80 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_skus_for_80pct_value,
       ROUND(100.0 * SUM(CASE WHEN cum_value_share <= 0.95 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_skus_for_95pct_value
FROM sku_abc_xyz;

-- AB5: What does each value quintile (NTILE 5) look like: value, variability and how many are seasonal?
SELECT value_quintile,
       COUNT(*)                         AS skus,
       ROUND(MIN(net_value_52w), 0)     AS min_value,
       ROUND(MAX(net_value_52w), 0)     AS max_value,
       ROUND(AVG(cv), 2)                AS avg_cv,
       SUM(is_seasonal)                 AS seasonal_skus
FROM sku_abc_xyz
GROUP BY value_quintile
ORDER BY value_quintile;

-- AB6: Which SKUs are in the top 10% by value (PERCENT_RANK >= 0.9) but erratic (Z)? These need the most care.
SELECT a.stock_code,
       ROUND(a.net_value_52w, 0)        AS net_value_52w,
       ROUND(a.value_percent_rank, 3)   AS value_percent_rank,
       ROUND(a.cv, 2)                   AS cv,
       a.abc, a.xyz
FROM sku_abc_xyz a
WHERE a.value_percent_rank >= 0.9
  AND a.xyz = 'Z'
ORDER BY a.net_value_52w DESC;

-- AB7: Within each ABC class, which are the 3 most erratic SKUs? (RANK ... PARTITION BY)
WITH ranked AS (
    SELECT stock_code, abc, xyz, cv,
           RANK() OVER (PARTITION BY abc ORDER BY cv DESC) AS cv_rank_in_class
    FROM sku_abc_xyz
)
SELECT abc, cv_rank_in_class, stock_code, ROUND(cv, 2) AS cv, xyz
FROM ranked
WHERE cv_rank_in_class <= 3
ORDER BY abc, cv_rank_in_class;
