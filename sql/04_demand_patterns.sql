/* =====================================================================
   04 · Demand patterns: trend, change and seasonality per SKU
   Window functions on the weekly demand table: rolling averages, LAG / LEAD, year-on-year.
   ===================================================================== */

-- DP1: For one SKU, what is the 4-week and 13-week rolling average demand, and how did each week change vs the week before?
SELECT stock_code,
       week_no,
       week_start,
       demand_units,
       ROUND(AVG(demand_units) OVER w4, 1)                       AS rolling_4wk_avg,
       ROUND(AVG(demand_units) OVER w13, 1)                      AS rolling_13wk_avg,
       demand_units - LAG(demand_units) OVER (PARTITION BY stock_code ORDER BY week_no)  AS change_vs_last_week,
       LEAD(demand_units) OVER (PARTITION BY stock_code ORDER BY week_no)                AS next_week_units
FROM weekly_demand
WHERE stock_code = '85123A'                                     -- white hanging heart t-light holder; change to any SKU
WINDOW w4  AS (PARTITION BY stock_code ORDER BY week_no ROWS BETWEEN 3 PRECEDING AND CURRENT ROW),
       w13 AS (PARTITION BY stock_code ORDER BY week_no ROWS BETWEEN 12 PRECEDING AND CURRENT ROW)
ORDER BY week_no;

-- DP2: Is demand growing? Compare each SKU's same 39 weeks this year vs last year using LAG(…, 52).
WITH yoy AS (
    SELECT stock_code, week_no, demand_units,
           LAG(demand_units, 52) OVER (PARTITION BY stock_code ORDER BY week_no) AS same_week_last_year
    FROM weekly_demand
)
SELECT a.abc,
       COUNT(DISTINCT y.stock_code)                                                  AS skus,
       SUM(y.demand_units)                                                           AS units_this_year,
       SUM(y.same_week_last_year)                                                    AS units_last_year,
       ROUND(100.0 * (SUM(y.demand_units) - SUM(y.same_week_last_year)) / SUM(y.same_week_last_year), 1) AS growth_pct
FROM yoy y
JOIN sku_abc_xyz a ON a.stock_code = y.stock_code
WHERE y.week_no BETWEEN 53 AND 91                                -- weeks with a full year of history, training period only
GROUP BY a.abc
ORDER BY a.abc;

-- DP3: Which SKUs have the strongest Christmas peak? (Sep-Nov 2010 demand vs the training average)
SELECT a.stock_code,
       ROUND(a.peak_uplift, 2)   AS peak_uplift,
       a.is_seasonal,
       a.abc, a.xyz,
       m.chosen_method
FROM sku_abc_xyz a
JOIN model_params m ON m.stock_code = a.stock_code
ORDER BY a.peak_uplift DESC
LIMIT 15;

-- DP4: How seasonal is the whole range? Average demand per calendar month by year (both years side by side).
SELECT w.month,
       MIN(MONTH(w.week_start))                                                              AS month_no,
       ROUND(AVG(CASE WHEN w.week_start BETWEEN '2009-12-07' AND '2010-11-29' THEN t.units END), 0) AS avg_week_year1,
       ROUND(AVG(CASE WHEN w.week_start BETWEEN '2010-12-06' AND '2011-11-21' THEN t.units END), 0) AS avg_week_year2
FROM (SELECT week_no, SUM(demand_units) AS units FROM weekly_demand GROUP BY week_no) t
JOIN weeks w ON w.week_no = t.week_no
GROUP BY w.month
ORDER BY month_no;

-- DP5: How lumpy is demand? For each SKU, the longest run of consecutive zero-demand weeks (gaps-and-islands with ROW_NUMBER).
WITH flagged AS (
    SELECT stock_code, week_no,
           week_no - ROW_NUMBER() OVER (PARTITION BY stock_code ORDER BY week_no) AS island
    FROM weekly_demand
    WHERE demand_units = 0
),
runs AS (
    SELECT stock_code, island, COUNT(*) AS zero_run_weeks, MIN(week_no) AS from_week, MAX(week_no) AS to_week
    FROM flagged
    GROUP BY stock_code, island
)
SELECT stock_code, MAX(zero_run_weeks) AS longest_zero_run_weeks
FROM runs
GROUP BY stock_code
HAVING MAX(zero_run_weeks) >= 4
ORDER BY longest_zero_run_weeks DESC;

-- DP6: Rank SKUs by how much demand moved between consecutive weeks (average absolute week-on-week change as % of average demand).
WITH changes AS (
    SELECT stock_code, demand_units,
           ABS(demand_units - LAG(demand_units) OVER (PARTITION BY stock_code ORDER BY week_no)) AS abs_change
    FROM weekly_demand
    WHERE week_no >= 52
)
SELECT stock_code,
       ROUND(AVG(abs_change) / AVG(demand_units) * 100, 0)                          AS avg_weekly_swing_pct,
       DENSE_RANK() OVER (ORDER BY AVG(abs_change) / AVG(demand_units) DESC)       AS swing_rank
FROM changes
GROUP BY stock_code
ORDER BY swing_rank
LIMIT 10;
