# Power BI report: Inventory_Planning.pbip

Saved as a **Power BI Project** (`.pbip`): the model (`.SemanticModel/`, TMDL text files) and the report pages
(`.Report/`, JSON) are plain text, so changes show up clearly in Git.

## Open it
1. The CSV files it needs are already in `data/processed/` (they are in Git), so you don't have to run the notebooks first.
2. Open `Inventory_Planning.pbip` in Power BI Desktop (2024 or later).
3. The `DataFolder` parameter defaults to `C:\data\inventory\`. Either copy the CSV files from `data/processed/` there, or go to
   **Home › Transform data › Edit parameters** and set it to the full path of your own `data\processed\` folder (ending with `\`).
4. **Home › Refresh.** Then **File › Save as** a `.pbix` if you want a single file.

## Pages

| Page | What it shows |
|---|---|
| Inventory Overview | KPI cards (current vs recommended stock £, working capital freed, safety stock £, SKUs to reorder, overstocked); stock by ABC-XYZ class; working capital freed by class; the service level vs safety stock curve; weeks of cover by XYZ class |
| ABC-XYZ Matrix | The 9-box as three matrices (SKU count, share of value, recommended stock £); scatter of value vs variability (CV); SKU table with class, CV, Christmas uplift and forecast method |
| Forecast vs Actual | Product slicer; actual weekly demand vs the chosen method (backtest Sep–Nov 2011 and the future forecast to Feb 2012); all four methods; error score by class and method |
| Reorder & At-risk | The SKU list with current stock, safety stock, reorder point, EOQ, max level, suggested order quantity, stock-out risk % and status, sorted by risk |

**What-if slicers:** *Service level* (80%–99.5%) and *Lead time* (1–12 weeks) on the Overview and Reorder pages.
Every policy number is a DAX measure, so it recalculates when you change them. Nothing selected = the defaults (95%, 3 weeks).
The other assumptions (holding cost 25%, £50 per order, unit cost 60% of price, current stock = 8 weeks of cover) are simple
measures in the `1 Assumptions` folder: change the number in the measure to try another value.

The numbers match the Excel model and the SQL exactly at the default assumptions (for example £294.8k current stock,
£270.9k recommended, 29 SKUs to reorder).

## Model

```
          Products (150 SKUs: class, CV, price, chosen method) ──┬──► WeeklyDemand (150 x 103 weeks)
                                                                  ├──► Forecasts   (backtest + future, 4 methods)
                                     Weeks (115 weeks) ───────────┤
                                                                  └──► Accuracy    (errors per SKU and method)
 Disconnected:  MethodByClass (score per class and method)   ·   'Service Level', 'Lead Time' (what-if slicers)
                'Service Level Curve' (x-axis of the trade-off chart)
```

All relationships are one-to-many, single direction, from the lookup table (Products, Weeks) to the fact tables.
`Products[Chosen Method]` is a calculated column: the method flagged `is_chosen` in the Forecasts table.

## Measures (41, in the `_Measures` table)

| Folder | Measures |
|---|---|
| 1 Assumptions | Service Level %, z (= NORM.S.INV), Lead Time (wks), Holding Cost Rate, Ordering Cost, Unit Cost Ratio, Current Cover Weeks |
| 2 Policy (units) | SKUs, Lead Time Demand, Safety Stock, Reorder Point, EOQ, Max Level, Current Stock, Suggested Order Qty, SKUs Reorder Now, SKUs Overstock, Stock Status, Stock-out Risk %, Weeks of Cover (Recommended / Current), Avg CV |
| 3 Stock value (£) | Current Stock Value, Recommended Stock Value, Working Capital Freed, Safety Stock Value, Suggested Order Value, Holding Cost per Year, Safety Stock Value at Curve SL, Net Sales 52w, Value Share % (+ two £k display versions) |
| 4 Forecast accuracy | Actual Units, Forecast (Chosen Method), Forecast Units, WAPE, Bias, WAPE (Chosen), Bias (Chosen), Class Score |

**The one DAX pattern to understand: `SUMX` over Products.** Safety stock and EOQ are per-SKU formulas (square roots, rounding up),
so they can't be added up first and calculated after. Each policy measure loops over the SKUs in the current filter,
calculates the SKU's value, then adds them up:

```dax
Safety Stock =
VAR _lt = [Lead Time (wks)]
VAR _z  = [z]
RETURN
    SUMX ( Products, ROUNDUP ( _z * Products[sd_weekly_52w] * SQRT ( _lt ), 0 ) )
```

The slicer values are read once into variables (`VAR`) before the loop, which is both faster and easier to read.
Lead-time demand uses `CALCULATE` inside the loop: for each SKU it sums that SKU's chosen-method forecast for the first
`_lt` future weeks.
