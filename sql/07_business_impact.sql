/* =====================================================================
   07 · Business impact: current vs recommended stock, working capital, stock-out risk, service-level trade-off
   "Current stock" is an assumption (8 weeks of average demand for every SKU), because the data has no stock levels.
   With a real stock file you would replace current_stock in inventory_policy and re-run this file.
   ===================================================================== */

-- BI1: In total, how much stock (£ at cost) do we hold today vs the recommended policy, and how much working capital is freed?
SELECT COUNT(*)                                                        AS skus,
       ROUND(SUM(current_stock_value), 0)                              AS current_stock_value,
       ROUND(SUM(recommended_stock_value), 0)                          AS recommended_stock_value,
       ROUND(SUM(current_stock_value) - SUM(recommended_stock_value), 0) AS working_capital_freed,
       ROUND(100 * (1 - SUM(recommended_stock_value) / SUM(current_stock_value)), 1) AS stock_reduction_pct,
       ROUND(SUM(current_stock_value - recommended_stock_value) * 0.25, 0) AS holding_cost_saved_per_year
FROM inventory_policy;

-- BI2: Where does the change come from? Current vs recommended stock value and SKU status counts by ABC-XYZ box.
SELECT abc_xyz,
       COUNT(*)                                                            AS skus,
       ROUND(SUM(current_stock_value), 0)                                  AS current_value,
       ROUND(SUM(recommended_stock_value), 0)                              AS recommended_value,
       ROUND(SUM(current_stock_value) - SUM(recommended_stock_value), 0)   AS value_freed,
       SUM(CASE WHEN stock_status = 'Reorder now' THEN 1 ELSE 0 END)        AS reorder_now,
       SUM(CASE WHEN stock_status = 'Overstock'   THEN 1 ELSE 0 END)        AS overstock
FROM inventory_policy
GROUP BY abc_xyz
ORDER BY abc_xyz;

-- BI3: Reorder list: which SKUs are at or below their reorder point today, and how much should we order? (biggest shortfall first)
SELECT stock_code, abc_xyz, chosen_method,
       current_stock,
       reorder_point,
       max_level,
       suggested_order_qty,
       ROUND(suggested_order_qty * unit_cost, 0)                        AS order_value,
       ROUND(weeks_cover_current, 1)                                    AS weeks_cover_now,
       ROUND((reorder_point - current_stock) * unit_cost, 0)            AS shortfall_value
FROM inventory_policy
WHERE stock_status = 'Reorder now'
ORDER BY shortfall_value DESC;

-- BI4: Overstock list: which SKUs hold more than their max level, and how much cash is tied up above max?
SELECT stock_code, abc_xyz,
       current_stock,
       max_level,
       current_stock - max_level                                         AS units_above_max,
       ROUND((current_stock - max_level) * unit_cost, 0)                 AS value_above_max,
       ROUND(weeks_cover_current - max_level / avg_weekly_52w, 1)        AS extra_weeks_of_cover
FROM inventory_policy
WHERE stock_status = 'Overstock'
ORDER BY value_above_max DESC
LIMIT 20;

-- BI5: Service level vs cost: how much safety stock (£) and holding cost does each service level need? (z = NORM.S.INV(service level))
WITH levels AS (
    SELECT 0.80 AS service_level, 0.841621 AS z UNION ALL
    SELECT 0.85, 1.036433 UNION ALL
    SELECT 0.90, 1.281552 UNION ALL
    SELECT 0.95, 1.644854 UNION ALL
    SELECT 0.975, 1.959964 UNION ALL
    SELECT 0.99, 2.326348 UNION ALL
    SELECT 0.995, 2.575829
),
base AS (                                   -- safety stock per 1 unit of z, at cost (sigma x SQRT(L) x unit cost)
    SELECT SUM(i.sd_weekly_52w * SQRT(p.lead_time_weeks) * i.unit_cost) AS ss_value_per_z,
           MAX(p.holding_cost_rate)                                     AS holding_rate
    FROM inventory_policy i
    CROSS JOIN planning_assumptions p
)
SELECT l.service_level,
       l.z,
       ROUND(l.z * b.ss_value_per_z, 0)                                        AS safety_stock_value,
       ROUND(l.z * b.ss_value_per_z * b.holding_rate, 0)                       AS holding_cost_per_year,
       ROUND(l.z * b.ss_value_per_z - LAG(l.z * b.ss_value_per_z) OVER (ORDER BY l.service_level), 0) AS extra_vs_previous_level
FROM levels l
CROSS JOIN base b
ORDER BY l.service_level;

-- BI6: Is the blanket 8-week rule wrong in both directions? Count SKUs where current stock is below the recommended average stock vs above it, by XYZ.
SELECT xyz,
       COUNT(*)                                                                  AS skus,
       SUM(CASE WHEN current_stock < avg_stock_recommended THEN 1 ELSE 0 END)     AS under_stocked_vs_policy,
       SUM(CASE WHEN current_stock >= avg_stock_recommended THEN 1 ELSE 0 END)    AS over_stocked_vs_policy,
       ROUND(AVG(weeks_cover_recommended), 1)                                    AS avg_weeks_cover_recommended
FROM inventory_policy
GROUP BY xyz
ORDER BY xyz;
