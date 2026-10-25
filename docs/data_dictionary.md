# Data dictionary

All tables are in `data/processed/`. Everything except `order_lines.csv` is in Git (small files), so Excel and Power BI
work straight after cloning. `order_lines.csv` (~90 MB) is rebuilt by `notebooks/01_data_prep.ipynb`.

## order_lines.csv (notebook 01, not in Git)
Clean invoice lines, same cleaning rules as Project 2. One row = one product on one invoice. 1,021,120 rows.

| Column | Meaning |
|---|---|
| invoice_no | invoice number; starts with `C` for credit notes (returns) |
| invoice_date | date of the invoice |
| line_type | `Sale` or `Return` |
| stock_code | product code (upper case) |
| quantity | units; negative on returns |
| unit_price | selling price per unit, £ |
| line_value | quantity × unit price, £ (negative on returns) |
| customer_id | customer number, `Unknown` if blank |
| country | customer's country |

## weeks.csv (notebook 01) · 115 rows
| Column | Meaning |
|---|---|
| week_no | 1 = week starting Mon 07-Dec-2009 … 103 = 21-Nov-2011 … 115 = 13-Feb-2012 |
| week_start | Monday of the week |
| period | `Train` (1–91), `Test` (92–103), `Future` (104–115) |
| in_last_52 | TRUE for weeks 52–103, the year used for averages, CV and ABC value |
| year, month | calendar year and month of week_start |

## weekly_demand.csv (notebook 01; rebuilt in `sql/02`) · 15,450 rows = 150 SKUs × 103 weeks
| Column | Meaning |
|---|---|
| stock_code, week_no, week_start, period | keys, see above |
| units_sold | units on sale lines that week |
| units_returned | units on credit notes that week (positive number) |
| demand_units | **net demand** = max(units_sold − units_returned, 0). Zero weeks are included |
| sales_value | £ of sale lines |
| net_value | £ of sales minus returns |

## sku_list.csv (notebook 01; rebuilt in `sql/03`) · 150 rows
All statistics use the last 52 weeks (weeks 52–103) unless noted.

| Column | Meaning |
|---|---|
| stock_code, description | product; description = the most common name used for the code |
| value_rank | 1 = highest net sales value |
| net_value_52w | net sales £ |
| units_52w | sum of demand_units |
| avg_price | sales value ÷ units sold (sale lines only) |
| avg_weekly_52w | average weekly demand (units) |
| sd_weekly_52w | sample standard deviation of weekly demand (`STDEV.S`) |
| cv | sd ÷ average = coefficient of variation |
| cum_value_share | running share of value when sorted from biggest to smallest |
| abc | A (cum share ≤ 80%), B (≤ 95%), C |
| xyz | X (CV ≤ 0.75), Y (≤ 1.25), Z (above) |
| abc_xyz | the 9-box class, e.g. `AY` |
| weeks_with_sales | number of the 103 weeks with any sale (all planning SKUs have ≥ 69) |
| peak_uplift | average demand weeks 40–52 (Sep–Nov 2010) ÷ average of training weeks 1–91 |
| is_seasonal | peak_uplift ≥ 1.3 (Holt-Winters allowed) |

## model_params.csv (notebook 02) · 150 rows
| Column | Meaning |
|---|---|
| ses_alpha | SES smoothing factor α with the lowest one-step error on weeks 1–91 (grid 0.05–0.95) |
| hw_alpha, hw_beta, hw_gamma | Holt-Winters level, trend and season factors (grid α 0.05–0.3, β 0–0.05, γ 0–0.2) |
| chosen_method | the method this SKU uses: its class winner, or the best non-seasonal method if the winner is Holt-Winters and the SKU isn't seasonal |

## forecasts.csv (notebook 02) · 14,400 rows = 150 SKUs × 4 methods × 2 runs × 12 weeks
| Column | Meaning |
|---|---|
| run | `Backtest` (made at the end of week 91 for weeks 92–103) or `Future` (made at the end of week 103 for weeks 104–115) |
| method | `Naive`, `Moving average`, `SES`, `Holt-Winters` |
| week_no, horizon | the week forecast and how many weeks ahead (1–12) |
| forecast_units | forecast demand |
| is_chosen | TRUE if this is the SKU's chosen method |

## forecast_accuracy.csv (notebook 02) · 600 rows = 150 SKUs × 4 methods
Over the 12 test weeks: `actual_units`, `forecast_units`, `sum_error` (Σ forecast − actual), `sum_abs_error`, `sum_sq_error`,
`wape`, `bias`, `mape` (weeks with actual > 0 only) and `weeks_nonzero`.

## method_by_class.csv (notebook 02; rebuilt in `sql/05`) · 36 rows = 9 classes × 4 methods
`skus`, `actual_units`, `sum_abs_error`, `sum_error`, `wape`, `bias`, `score` (= wape + |bias|), `rank` within the class, `is_best`.

## prep_log.csv (notebook 01)
Rows before / after each cleaning and preparation step.
