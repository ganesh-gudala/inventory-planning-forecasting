/* =====================================================================
   06 · Inventory policy per SKU: safety stock, reorder point, EOQ, min/max, weeks of cover
   The data has no lead times, costs or stock levels, so these are ASSUMPTIONS (see README). They sit in one
   table so they are easy to change; the Excel model and Power BI use the same defaults.

     service level 95%  -> z = 1.644854 (= NORM.S.INV(0.95) in Excel)
     lead time          3 weeks
     holding cost       25% of unit cost per year
     ordering cost      £50 per purchase order line
     unit cost          60% of the average selling price (the data only has selling prices)
     current stock      8 weeks of average demand for every SKU (a blanket weeks-of-cover rule)

   Formulas (d = average weekly demand, sigma = standard deviation of weekly demand, L = lead time in weeks):
     safety stock   SS  = z x sigma x SQRT(L)                         rounded up to whole units
     reorder point  ROP = forecast demand over the lead time + SS     (forecast = the SKU's chosen method)
     EOQ                = SQRT(2 x annual demand x ordering cost / (holding % x unit cost))
     min = ROP, max = ROP + EOQ, average stock = SS + EOQ / 2
   ===================================================================== */

-- IP1: Which planning assumptions are we using? (one row; change the numbers here to re-run the policy)
DROP TABLE IF EXISTS planning_assumptions;
CREATE TABLE planning_assumptions AS
SELECT 0.95   AS service_level,
       1.644854 AS z,
       3      AS lead_time_weeks,
       0.25   AS holding_cost_rate,
       50.00  AS ordering_cost,
       0.60   AS unit_cost_ratio,
       8      AS current_cover_weeks;

SELECT * FROM planning_assumptions;

-- IP2: What is the recommended stock policy for every SKU? (builds inventory_policy)
DROP TABLE IF EXISTS inventory_policy;
CREATE TABLE inventory_policy AS
WITH lead_time_forecast AS (                  -- demand expected during the lead time, from the chosen method
    SELECT f.stock_code, SUM(f.forecast_units) AS lt_demand
    FROM forecasts f
    CROSS JOIN planning_assumptions p
    WHERE f.run = 'Future' AND f.is_chosen = 'True' AND f.horizon <= p.lead_time_weeks
    GROUP BY f.stock_code
),
base AS (
    SELECT a.stock_code, a.abc, a.xyz, CONCAT(a.abc, a.xyz) AS abc_xyz, m.chosen_method,
           a.avg_weekly_52w, a.sd_weekly_52w,
           a.avg_price * p.unit_cost_ratio                                         AS unit_cost,
           a.avg_weekly_52w * 52                                                   AS annual_units,
           t.lt_demand,
           CEIL(p.z * a.sd_weekly_52w * SQRT(p.lead_time_weeks))                   AS safety_stock,
           CEIL(SQRT(2 * a.avg_weekly_52w * 52 * p.ordering_cost
                     / (p.holding_cost_rate * a.avg_price * p.unit_cost_ratio)))   AS eoq,
           ROUND(p.current_cover_weeks * a.avg_weekly_52w, 0)                      AS current_stock
    FROM sku_abc_xyz a
    JOIN model_params m        ON m.stock_code = a.stock_code
    JOIN lead_time_forecast t  ON t.stock_code = a.stock_code
    CROSS JOIN planning_assumptions p
)
SELECT b.*,
       CEIL(lt_demand) + safety_stock                          AS reorder_point,
       CEIL(lt_demand) + safety_stock                          AS min_level,
       CEIL(lt_demand) + safety_stock + eoq                    AS max_level,
       safety_stock + eoq / 2.0                                AS avg_stock_recommended,
       (safety_stock + eoq / 2.0) / avg_weekly_52w             AS weeks_cover_recommended,
       current_stock / avg_weekly_52w                          AS weeks_cover_current,
       current_stock * unit_cost                               AS current_stock_value,
       (safety_stock + eoq / 2.0) * unit_cost                  AS recommended_stock_value,
       CASE WHEN current_stock <= CEIL(lt_demand) + safety_stock       THEN 'Reorder now'
            WHEN current_stock >  CEIL(lt_demand) + safety_stock + eoq THEN 'Overstock'
            ELSE 'OK' END                                      AS stock_status,
       CASE WHEN current_stock <= CEIL(lt_demand) + safety_stock
            THEN CEIL(lt_demand) + safety_stock + eoq - current_stock ELSE 0 END AS suggested_order_qty
FROM base b;

-- IP3: Show the policy for the 15 most valuable SKUs (what a planner would check first).
SELECT p.stock_code, p.abc_xyz, p.chosen_method,
       ROUND(p.avg_weekly_52w, 0)  AS avg_weekly,
       ROUND(p.lt_demand, 0)       AS lead_time_demand,
       p.safety_stock, p.reorder_point, p.eoq, p.min_level, p.max_level,
       ROUND(p.weeks_cover_recommended, 1) AS weeks_cover_rec,
       p.stock_status
FROM inventory_policy p
JOIN sku_abc_xyz a ON a.stock_code = p.stock_code
ORDER BY a.net_value_52w DESC
LIMIT 15;

-- IP4: How do safety stock and weeks of cover differ across the 9 boxes? (erratic Z SKUs should need far more buffer)
SELECT abc_xyz,
       COUNT(*)                                                  AS skus,
       ROUND(SUM(safety_stock * unit_cost), 0)                   AS safety_stock_value,
       ROUND(AVG(safety_stock / avg_weekly_52w), 1)              AS avg_safety_weeks,
       ROUND(AVG(eoq / avg_weekly_52w), 1)                       AS avg_order_cycle_weeks,
       ROUND(AVG(weeks_cover_recommended), 1)                    AS avg_weeks_cover_rec
FROM inventory_policy
GROUP BY abc_xyz
ORDER BY abc_xyz;

-- IP5: Check the policy logic: every SKU must have SS >= 0, ROP >= SS, max > min and an EOQ of at least 1 (should return 0 rows).
SELECT stock_code, safety_stock, reorder_point, eoq, min_level, max_level
FROM inventory_policy
WHERE safety_stock < 0 OR reorder_point < safety_stock OR max_level <= min_level OR eoq < 1;
