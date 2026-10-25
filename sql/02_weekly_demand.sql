/* =====================================================================
   02 · Weekly demand tables
   Turns invoice lines into one row per SKU per week: net demand = units sold - units returned.
   Builds three tables used by everything after this:
     sku_week_demand   every SKU, only the weeks it had activity (sales or returns)
     planning_skus     the 150 SKUs we plan: top by net value in the last 52 weeks, sold in >= 69 of 103 weeks
     weekly_demand     150 SKUs x 103 weeks, zero weeks filled in, negative net weeks set to 0
   ===================================================================== */

-- WD1: Does the planning calendar have 103 full Monday-to-Sunday weeks with no gaps? (recursive CTE builds the expected list)
WITH RECURSIVE expected AS (
    SELECT 1 AS week_no, DATE '2009-12-07' AS week_start
    UNION ALL
    SELECT week_no + 1, DATE_ADD(week_start, INTERVAL 7 DAY)
    FROM expected
    WHERE week_no < 103
)
SELECT COUNT(*)                                                    AS expected_weeks,
       SUM(CASE WHEN w.week_start = e.week_start THEN 1 ELSE 0 END) AS weeks_matching_calendar,
       MIN(e.week_start)                                           AS first_week,
       MAX(e.week_start)                                           AS last_week
FROM expected e
LEFT JOIN weeks w ON w.week_no = e.week_no;

-- WD2: How much demand (units sold and returned) does every SKU have in each week? (all SKUs, 103 full weeks only)
DROP TABLE IF EXISTS sku_week_demand;
CREATE TABLE sku_week_demand AS
WITH lines AS (
    SELECT stock_code,
           FLOOR(DATEDIFF(invoice_date, '2009-12-07') / 7) + 1 AS week_no,   -- week 1 starts Mon 07-Dec-2009
           CASE WHEN line_type = 'Sale'   THEN quantity  ELSE 0 END    AS sold,
           CASE WHEN line_type = 'Return' THEN -quantity ELSE 0 END    AS returned,
           CASE WHEN line_type = 'Sale'   THEN line_value ELSE 0 END  AS sales_value,
           line_value
    FROM order_lines
    WHERE invoice_date BETWEEN '2009-12-07' AND '2011-11-27'          -- drops the partial first week and Dec-2011
)
SELECT stock_code,
       week_no,
       SUM(sold)                  AS units_sold,
       SUM(returned)              AS units_returned,
       SUM(sold) - SUM(returned)  AS net_units,
       SUM(sales_value)           AS sales_value,
       SUM(line_value)            AS net_value
FROM lines
GROUP BY stock_code, week_no;

-- WD3: Which 150 SKUs should we plan? Top net sales value in the last 52 weeks, among SKUs that sell regularly.
DROP TABLE IF EXISTS planning_skus;
CREATE TABLE planning_skus AS
WITH sku_totals AS (
    SELECT stock_code,
           SUM(CASE WHEN week_no >= 52 THEN net_value ELSE 0 END)     AS net_value_52w,
           SUM(CASE WHEN units_sold > 0 THEN 1 ELSE 0 END)            AS weeks_with_sales
    FROM sku_week_demand
    GROUP BY stock_code
),
ranked AS (
    SELECT stock_code, net_value_52w, weeks_with_sales,
           ROW_NUMBER() OVER (ORDER BY net_value_52w DESC)                           AS rank_all_skus,
           ROW_NUMBER() OVER (PARTITION BY weeks_with_sales >= 69 ORDER BY net_value_52w DESC) AS rank_in_group
    FROM sku_totals
)
SELECT stock_code, net_value_52w, weeks_with_sales, rank_all_skus, rank_in_group AS value_rank
FROM ranked
WHERE weeks_with_sales >= 69
  AND rank_in_group <= 150;

-- WD4: What is the weekly net demand of each planning SKU, including weeks with no sales? (grid = SKUs x weeks)
DROP TABLE IF EXISTS weekly_demand;
CREATE TABLE weekly_demand AS
SELECT p.stock_code,
       w.week_no,
       w.week_start,
       w.period,
       COALESCE(d.units_sold, 0)                    AS units_sold,
       COALESCE(d.units_returned, 0)                AS units_returned,
       GREATEST(COALESCE(d.net_units, 0), 0)        AS demand_units,     -- a negative week isn't demand
       COALESCE(d.sales_value, 0)                   AS sales_value,
       COALESCE(d.net_value, 0)                     AS net_value
FROM planning_skus p
CROSS JOIN weeks w
LEFT JOIN sku_week_demand d
       ON d.stock_code = p.stock_code AND d.week_no = w.week_no
WHERE w.week_no <= 103;

-- WD5: How many SKU-weeks had zero demand or were negative before flooring, and what share of the range is that?
SELECT COUNT(*)                                                  AS sku_weeks,
       SUM(CASE WHEN demand_units = 0 THEN 1 ELSE 0 END)          AS zero_weeks,
       ROUND(100.0 * SUM(CASE WHEN demand_units = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS zero_week_pct,
       SUM(CASE WHEN units_sold - units_returned < 0 THEN 1 ELSE 0 END) AS negative_weeks_floored
FROM weekly_demand;

-- WD6: What share of the whole business do the 150 planning SKUs cover? (value in the last 52 weeks)
SELECT COUNT(DISTINCT s.stock_code)                                                         AS all_skus,
       ROUND(SUM(s.net_value), 0)                                                           AS all_net_value_52w,
       ROUND(SUM(CASE WHEN p.stock_code IS NOT NULL THEN s.net_value ELSE 0 END), 0)        AS planned_net_value_52w,
       ROUND(100.0 * SUM(CASE WHEN p.stock_code IS NOT NULL THEN s.net_value ELSE 0 END) / SUM(s.net_value), 1) AS planned_share_pct
FROM sku_week_demand s
LEFT JOIN planning_skus p ON p.stock_code = s.stock_code
WHERE s.week_no >= 52;

-- WD7: How does total weekly demand of the planning range move, with a 4-week rolling average to show the trend?
SELECT week_no,
       week_start,
       SUM(demand_units)                                                                 AS demand_units,
       ROUND(AVG(SUM(demand_units)) OVER (ORDER BY week_no ROWS BETWEEN 3 PRECEDING AND CURRENT ROW), 0) AS rolling_4wk_avg
FROM weekly_demand
GROUP BY week_no, week_start
ORDER BY week_no;
