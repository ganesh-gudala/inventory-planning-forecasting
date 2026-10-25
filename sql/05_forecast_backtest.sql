/* =====================================================================
   05 · Forecast backtest: how accurate is each method, and which one should each class use?
   Train = weeks 1-91, Test = weeks 92-103 (05-Sep to 27-Nov-2011), forecast made once at the end of week 91.
   Naive and moving average are simple enough to calculate here in SQL (FC1-FC2) and are checked against the
   Python batch run. SES and Holt-Winters are recursive, so they come from notebook 02 (the forecasts table).

   WAPE = SUM(|forecast - actual|) / SUM(actual)       bias = SUM(forecast - actual) / SUM(actual)
   ===================================================================== */

-- FC1: What would naive (last week) and an 8-week moving average have forecast for the test weeks, and how wrong were they?
WITH origin AS (                                       -- the state of each SKU at the end of week 91
    SELECT stock_code,
           MAX(CASE WHEN week_no = 91 THEN demand_units END)        AS last_week_units,
           AVG(CASE WHEN week_no BETWEEN 84 AND 91 THEN demand_units END) AS avg_last_8_weeks
    FROM weekly_demand
    GROUP BY stock_code
)
SELECT a.abc,
       ROUND(SUM(ABS(o.last_week_units  - d.demand_units)) / SUM(d.demand_units), 3) AS naive_wape,
       ROUND(SUM(o.last_week_units  - d.demand_units)      / SUM(d.demand_units), 3) AS naive_bias,
       ROUND(SUM(ABS(o.avg_last_8_weeks - d.demand_units)) / SUM(d.demand_units), 3) AS ma8_wape,
       ROUND(SUM(o.avg_last_8_weeks - d.demand_units)      / SUM(d.demand_units), 3) AS ma8_bias
FROM weekly_demand d
JOIN origin o      ON o.stock_code = d.stock_code
JOIN sku_abc_xyz a ON a.stock_code = d.stock_code
WHERE d.period = 'Test'
GROUP BY a.abc
ORDER BY a.abc;

-- FC2: Do the SQL naive and moving-average forecasts match the Python batch run? (should return 0 mismatches)
WITH origin AS (
    SELECT stock_code,
           MAX(CASE WHEN week_no = 91 THEN demand_units END)              AS naive_fc,
           AVG(CASE WHEN week_no BETWEEN 84 AND 91 THEN demand_units END) AS ma_fc
    FROM weekly_demand
    GROUP BY stock_code
)
SELECT f.method, COUNT(*) AS rows_checked,
       SUM(CASE WHEN ABS(f.forecast_units - CASE WHEN f.method = 'Naive' THEN o.naive_fc ELSE o.ma_fc END) > 0.001
                THEN 1 ELSE 0 END) AS mismatches
FROM forecasts f
JOIN origin o ON o.stock_code = f.stock_code
WHERE f.run = 'Backtest' AND f.method IN ('Naive', 'Moving average')
GROUP BY f.method;

-- FC3: Across all 150 SKUs, which method had the lowest WAPE and the smallest bias in the backtest?
SELECT f.method,
       ROUND(SUM(ABS(f.forecast_units - d.demand_units)) / SUM(d.demand_units), 3) AS wape,
       ROUND(SUM(f.forecast_units - d.demand_units) / SUM(d.demand_units), 3)      AS bias,
       ROUND(AVG(CASE WHEN d.demand_units > 0
                      THEN ABS(f.forecast_units - d.demand_units) / d.demand_units END), 3) AS mape_nonzero_weeks
FROM forecasts f
JOIN weekly_demand d ON d.stock_code = f.stock_code AND d.week_no = f.week_no
WHERE f.run = 'Backtest'
GROUP BY f.method
ORDER BY wape;

-- FC4: Best method per ABC-XYZ class: lowest WAPE + |bias|, using ROW_NUMBER to pick the winner in each class.
DROP TABLE IF EXISTS method_by_class_sql;
CREATE TABLE method_by_class_sql AS
WITH class_errors AS (
    SELECT CONCAT(a.abc, a.xyz)                                          AS abc_xyz,
           f.method,
           COUNT(DISTINCT f.stock_code)                                  AS skus,
           SUM(ABS(f.forecast_units - d.demand_units)) / SUM(d.demand_units) AS wape,
           SUM(f.forecast_units - d.demand_units) / SUM(d.demand_units)      AS bias
    FROM forecasts f
    JOIN weekly_demand d ON d.stock_code = f.stock_code AND d.week_no = f.week_no
    JOIN sku_abc_xyz a   ON a.stock_code = f.stock_code
    WHERE f.run = 'Backtest'
    GROUP BY CONCAT(a.abc, a.xyz), f.method
)
SELECT abc_xyz, method, skus, wape, bias,
       wape + ABS(bias)                                                       AS score,
       ROW_NUMBER() OVER (PARTITION BY abc_xyz ORDER BY wape + ABS(bias))     AS method_rank
FROM class_errors;

SELECT abc_xyz, method AS best_method, skus, ROUND(wape, 3) AS wape, ROUND(bias, 3) AS bias, ROUND(score, 3) AS score
FROM method_by_class_sql
WHERE method_rank = 1
ORDER BY abc_xyz;

-- FC5: Which method does each SKU use? (class winner; non-seasonal SKUs fall back to the best non-Holt-Winters method) and does it match Python?
WITH best_any AS (
    SELECT abc_xyz, method FROM method_by_class_sql WHERE method_rank = 1
),
best_flat AS (
    SELECT abc_xyz, method
    FROM (SELECT abc_xyz, method,
                 ROW_NUMBER() OVER (PARTITION BY abc_xyz ORDER BY score) AS rn
          FROM method_by_class_sql
          WHERE method <> 'Holt-Winters') t
    WHERE rn = 1
),
choice AS (
    SELECT a.stock_code,
           CASE WHEN b.method = 'Holt-Winters' AND a.is_seasonal = 0 THEN f.method ELSE b.method END AS chosen_method_sql
    FROM sku_abc_xyz a
    JOIN best_any  b ON b.abc_xyz = CONCAT(a.abc, a.xyz)
    JOIN best_flat f ON f.abc_xyz = CONCAT(a.abc, a.xyz)
)
SELECT c.chosen_method_sql,
       COUNT(*)                                                                AS skus,
       SUM(CASE WHEN c.chosen_method_sql <> m.chosen_method THEN 1 ELSE 0 END)  AS mismatches_vs_python
FROM choice c
JOIN model_params m ON m.stock_code = c.stock_code
GROUP BY c.chosen_method_sql
ORDER BY skus DESC;

-- FC6: How accurate is the chosen method per class, week by week? (total forecast vs actual for the test weeks)
SELECT w.week_no,
       w.week_start,
       SUM(d.demand_units)                         AS actual_units,
       ROUND(SUM(f.forecast_units), 0)             AS chosen_forecast_units,
       ROUND(SUM(f.forecast_units) - SUM(d.demand_units), 0) AS error_units,
       ROUND(SUM(SUM(f.forecast_units) - SUM(d.demand_units)) OVER (ORDER BY w.week_no), 0) AS cumulative_error
FROM forecasts f
JOIN weekly_demand d ON d.stock_code = f.stock_code AND d.week_no = f.week_no
JOIN weeks w         ON w.week_no = f.week_no
WHERE f.run = 'Backtest' AND f.is_chosen = 'True'
GROUP BY w.week_no, w.week_start
ORDER BY w.week_no;

-- FC7: Which 10 SKUs did the chosen method forecast worst (highest WAPE), so a planner can review them by hand?
SELECT f.stock_code,
       CONCAT(a.abc, a.xyz)                                                       AS abc_xyz,
       MAX(f.method)                                                              AS chosen_method,
       SUM(d.demand_units)                                                        AS actual_units,
       ROUND(SUM(f.forecast_units), 0)                                            AS forecast_units,
       ROUND(SUM(ABS(f.forecast_units - d.demand_units)) / SUM(d.demand_units), 2) AS wape
FROM forecasts f
JOIN weekly_demand d ON d.stock_code = f.stock_code AND d.week_no = f.week_no
JOIN sku_abc_xyz a   ON a.stock_code = f.stock_code
WHERE f.run = 'Backtest' AND f.is_chosen = 'True'
GROUP BY f.stock_code, CONCAT(a.abc, a.xyz)
ORDER BY wape DESC
LIMIT 10;
