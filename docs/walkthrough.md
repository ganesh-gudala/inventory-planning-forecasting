# Walkthrough: how this project works, step by step

Read this next to the files it mentions. It goes in the same order as the work: the question, the data, the weekly demand,
ABC–XYZ, forecasting, the stock policy, the business impact, and finally Excel, SQL and Power BI.
Words in *italics* are explained in [glossary.md](glossary.md).

---

## 0. The 30-second version

> "I used the same real UK retailer as my returns project and asked: how much stock should we hold of each product, and when
> should we reorder? I turned a million invoice lines into weekly demand for the top 150 products, classified them by value and
> predictability (ABC–XYZ), tested four forecasting methods on the Christmas run-up of 2011, and picked the best method for each class.
> Then I calculated safety stock, reorder points and order quantities. Compared with a blanket 8-weeks-of-cover rule, the policy
> frees about £24k (8%) of stock and, more importantly, moves stock from steady products to erratic ones, which were under-protected.
> The Excel model lets you change the service level, lead time and costs and see everything update."

---

## 1. The business question

*"How much stock should we hold for each product, and when should we reorder, so we don't run out or overstock?"*

Two ways to get it wrong:
- **Too little stock** → stock-outs → lost sales and unhappy customers.
- **Too much stock** → cash tied up (*working capital*), storage costs, products that go out of fashion.

Every inventory policy is a balance between the two. The tools to find the balance: a forecast (how much will we sell?),
a measure of uncertainty (how wrong could the forecast be?), and a few cost assumptions.

---

## 2. The data (`notebooks/01_data_prep.ipynb`, section 1)

The **UCI Online Retail II** dataset: every invoice line of a real UK online gift retailer, Dec-2009 to Dec-2011, ~1 million lines.
Most customers are small shops buying stock.

I cleaned it with **exactly the same rules as Project 2** (same row count: 1,021,120 clean lines), so the two projects tell one story:
remove duplicates, keep real products only, drop zero-price write-offs and two order-entry mistakes, label credit notes as returns.

**What the data does not have**, and how I handled it (say this early in an interview, it shows you understand the data):

| Missing | What I did |
|---|---|
| Stock levels | Assumed today's stock = 8 weeks of average demand for every SKU (a common blanket rule). Easy to replace with a real stock file |
| Lead times | Assumed 3 weeks (the brief said 2–4) |
| Costs | Unit cost = 60% of selling price; holding cost 25% a year; £50 per order |
| True demand | Only sales are recorded. If a product was out of stock, real demand was higher (*censored demand*). Can't be fixed without stock data |

---

## 3. From invoice lines to weekly demand (notebook 01, sections 2–3; `sql/02_weekly_demand.sql`)

**Why weekly?** Purchase orders and stock reviews happen weekly. Daily is too noisy, monthly too slow to react.

**The calendar.** Weeks run Monday–Sunday. The data starts on a Tuesday (1 Dec 2009), so the first full week starts Mon 7 Dec 2009.
The brief says to drop December 2011 (it's only 9 days). That leaves the week of 28 Nov 2011 with only 3 days, so it goes too.
Result: **103 full weeks**.

| Weeks | Use |
|---|---|
| 1–91 (Dec-2009 to Aug-2011) | Training: fit the forecast methods |
| 92–103 (Sep–Nov 2011) | Test: the 12-week backtest |
| 104–115 (Dec-2011 to Feb-2012) | Future: the forecast the stock policy uses |
| 52–103 (last 52 weeks) | Average demand, variability (CV) and value for ABC |

**Net demand** = units sold − units returned in the week. Two details:
- **Zero weeks are filled in.** If a product sold nothing in a week, that's a real week of 0, not a missing row.
  Leaving them out would make the average too high and the variability too low. In SQL this is a `CROSS JOIN` of SKUs × weeks
  with a `LEFT JOIN` to the sales (query WD4).
- **Negative weeks are set to 0.** A big return in a quiet week can make net demand negative. That's an old sale coming back,
  not negative demand. It happened in 107 of 15,450 SKU-weeks (0.7%).

---

## 4. Which products to plan (notebook 01, section 4; `sql/02` WD3)

There are 3,811 products. A planner focuses on the ones that matter most:
- ranked by **net sales value in the last 52 weeks**
- only **regular** products: sold in at least 69 of the 103 weeks (two-thirds). New or one-off products have too little history
  for a backtest; in real life they're planned with judgement.

The **top 150 regular products = 34.5%** of all sales. In SQL: `ROW_NUMBER() OVER (PARTITION BY weeks_with_sales >= 69 ORDER BY value DESC)`.

One data quirk worth mentioning: product 84347 has a credit note for 9,360 units at £0.03 (a correction, not a real return),
which made its net units negative. That's why the average price uses **sale lines only** (sales value ÷ units sold).

---

## 5. ABC–XYZ classification (notebook 01, section 6; `sql/03_abc_xyz.sql`; Excel sheet **ABC_XYZ**)

**ABC = value.** Sort products from biggest to smallest sales value and keep a running total.
- A = products in the first 80% of value
- B = the next 15% (up to 95%)
- C = the last 5%

In SQL: `SUM(value) OVER (ORDER BY value DESC ROWS UNBOUNDED PRECEDING) / SUM(value) OVER ()`.
In Excel: `SUMIFS(value, value, ">="&this_value) / SUM(value)` (the share of value from products at least this big).

**XYZ = predictability**, using the *CV* (standard deviation ÷ average of weekly demand):
- X = CV ≤ 0.75 (steady), Y = 0.75–1.25 (variable), Z = above 1.25 (erratic)

Why not the textbook 0.5 / 1.0? Those are for monthly data. Weekly demand for one product is much noisier: with 0.5, only 6 of
150 products would be X. The limits are inputs in Excel so you can try others.

**The result (9-box):**

| | X | Y | Z | Total |
|---|---|---|---|---|
| **A** | 36 | 31 | 28 | 95 |
| **B** | 10 | 17 | 12 | 39 |
| **C** | 5 | 7 | 4 | 16 |

**Likely question: "Why are 95 of 150 products A-class? Isn't it supposed to be 20%?"**
Because the range is already the top sellers. Across all 3,811 products, all 150 would be "A". Inside the top 150, value is
spread more evenly (63% of products make 80% of value). I kept the standard 80/15/5 split and explain it rather than bending the
thresholds to get a nicer-looking picture.

**How to use the 9-box:** AX (valuable, steady) = lean stock, automate. AZ (valuable, erratic) = the risky box: most safety stock,
most attention. CZ = consider make-to-order or delisting.

---

## 6. Forecasting (`notebooks/02_forecast_backtest.ipynb`; Excel sheets **Forecast** and **Backtest**; `sql/05`)

### 6.1 The four methods
| Method | Idea | In the Excel Forecast sheet |
|---|---|---|
| Naive | next week = last week | `=$D$<row of week 91>` |
| Moving average (8 weeks) | average of the last 8 weeks | `=AVERAGE(INDEX(D, 84):INDEX(D, 91))` |
| SES | smoothed level, recent weeks count more | `level = α × actual + (1−α) × last level` |
| Holt-Winters | level + trend + last year's seasonal pattern | three columns: level, trend, season |

Holt-Winters needs **start values**. Level = average of the first 52 weeks, trend = 0, and the seasonal effect of each week
in year 1 = a 9-week centred average around that week minus the level. The 9-week average stops one random spike from becoming
"the seasonal pattern".

**Parameters (α, β, γ)** are chosen per product by trying a small grid and keeping the values with the smallest one-step error
on the training weeks. Holt-Winters always picked γ = 0 (don't update the seasonal pattern): with one and a bit years of data
there's no second Christmas in the training weeks to learn from.

Holt-Winters is only **allowed for seasonal products** (Christmas uplift ≥ 1.3, i.e. Sep–Nov 2010 was at least 30% above the usual level).

### 6.2 The backtest
Pretend it's the end of August 2011. Fit on weeks 1–91, forecast weeks 92–103 in one go, and compare with what really happened.
The test period is September–November: the Christmas run-up, the hardest and most important period for a gift retailer.

### 6.3 Accuracy
- **WAPE** = Σ|error| ÷ Σactual: the main measure, because it works with zero weeks.
- **MAPE**: shown, but only over weeks with actual > 0 (it divides by the actual).
- **Bias** = Σerror ÷ Σactual: are we consistently too low (stock-outs) or too high (overstock)?

| Method (all 150 SKUs) | WAPE | Bias |
|---|---|---|
| Naive | 70% | −34% |
| Moving average | 60% | −23% |
| SES | 59% | −22% |
| Holt-Winters | 62% | +9% |
| **Chosen method per class** | **61%** | **+4%** |

**The key insight:** the three flat methods have similar WAPE but all **under-forecast by 20–35%**, because a flat forecast made in
August can't see the Christmas rise coming. For stock, that bias means running out exactly when demand peaks. Holt-Winters
expects the rise (bias +9%) but copies some of last year's noise, so its WAPE isn't better. That's why the selection uses
**WAPE + |bias|**.

WAPE of ~60% sounds bad, but it's normal for **weekly demand of single products** at a wholesaler (lumpy orders from shops).
Accuracy is much better when you add up weeks or products: that's why safety stock exists.

### 6.4 Best method per class
For each 9-box class, the method with the lowest WAPE + |bias| wins:

| Class | Best method | Why it makes sense |
|---|---|---|
| AX, BX, CX | Moving average / SES | steady demand: a smooth flat forecast is enough |
| AY, AZ, BY, BZ | Holt-Winters | variable, seasonal products: the Christmas pattern matters most |
| CY, CZ | SES | small, erratic: Holt-Winters over-reacts, a smooth average is safer |

Result: 54 products use Holt-Winters, 44 moving average, 40 SES, 12 naive (non-seasonal products in Holt-Winters classes fall back
to their class's best non-seasonal method).

**Likely question: "Why choose per class and not the best method for each product?"**
12 weeks is a short test. A single product's "best" method is often luck. Pooling the products in a class gives a more stable choice.

**Excel FORECAST.ETS** is shown next to my own Holt-Winters. It picks its own parameters and wasn't consistently better (WAPE 48% on 85123A,
95% on 22423, where the other methods were 26–51%). Good talking point: built-in functions aren't automatically better, you still have to test them.

---

## 7. The stock policy (`sql/06_inventory_policy.sql`; Excel sheet **Policy**; Power BI measures)

For every product (σ = standard deviation of weekly demand, L = lead time in weeks):

| Step | Formula | Example: 85123A (white heart t-light holder) |
|---|---|---|
| z | `NORM.S.INV(95%)` = 1.645 | 1.645 |
| Safety stock | z × σ × √L, rounded up | 1.645 × 520 × √3 = 1,481 |
| Lead-time demand | sum of the chosen forecast for the next 3 weeks | 1,907 (Holt-Winters, early December) |
| Reorder point (Min) | lead-time demand + safety stock | 3,388 |
| EOQ | √(2 × annual demand × £50 ÷ (25% × unit cost)) | 2,866 |
| Max | ROP + EOQ | 6,254 |
| Average stock | safety stock + EOQ ÷ 2 | 2,914 units = 4.4 weeks of cover |

**Why √L?** Over 3 weeks, a high week and a low week partly cancel out, so uncertainty grows with the square root of time, not in a straight line.

**Why the forecast in the ROP but σ of history in safety stock?** The forecast tells you the expected demand during the lead time
(including the Christmas rise for seasonal products). The safety stock covers the uncertainty around it, measured from how much
weekly demand moved over the last year. A refinement would be to use the forecast error (RMSE) instead; mentioned in the interview Q&A.

**Min/max** is how a warehouse uses it: when stock falls to Min, order enough to get back to Max.

---

## 8. Business impact (`sql/07_business_impact.sql`; Excel sheet **Summary**; Power BI **Inventory Overview**)

Compared with the assumed current rule (8 weeks of cover for every product), at 95% service level and 3-week lead time:

| | |
|---|---|
| Current stock (at cost) | £294.8k |
| Recommended average stock | £270.9k |
| **Working capital freed** | **£23.9k (8.1%)**, about £6k a year in holding cost |
| Products to reorder now | 29 (current stock at or below the reorder point) |
| Overstocked (above max) | 1 |

The headline saving is modest. **The real finding is the rebalancing:**

| | Current | Recommended | Change |
|---|---|---|---|
| X (steady) | £115.8k | £83.6k | **£32.2k too much** |
| Y (variable) | £100.2k | £92.2k | £7.9k too much |
| Z (erratic) | £78.8k | £95.1k | **£16.3k too little** |

A blanket weeks-of-cover rule gives steady products more stock than they need and erratic products less. 26 of the 29 "reorder now"
products are Z. So the policy isn't just "hold less stock", it's "hold stock where the risk is".

**Service level vs cost** (Summary sheet table, Overview page curve):

| Service level | z | Safety stock £ |
|---|---|---|
| 90% | 1.28 | £84.6k |
| 95% | 1.645 | £108.6k |
| 98% | 2.05 | £135.6k |
| 99% | 2.33 | £153.6k |

Going from 95% to 99% needs ~40% more safety stock. Each extra point costs more than the last. A good answer to "what service level
should we use?" is: it depends on the margin and the cost of a lost sale; differentiate by class (e.g. 98% for A, 90% for C), which
the Excel Inputs sheet lets you test.

---

## 9. The Excel model (`excel/Inventory_Planning_Model.xlsx`)

Every number is a live formula. Yellow cells are inputs. Click any cell and read the formula bar.

| Sheet | What to show in an interview | Key functions |
|---|---|---|
| Inputs | change service level to 98% and watch Summary | `NORM.S.INV`, data validation (drop-down limits), named ranges |
| ABC_XYZ | cumulative share and the 9-box | `SUMIFS`, `RANK.EQ`, `XLOOKUP` returning a whole row, `STDEV.S`, `COUNTIFS` |
| Forecast | pick a product in the drop-down; walk through the SES and Holt-Winters columns | `INDEX/MATCH`, `INDEX(...):INDEX(...)` ranges, `FORECAST.ETS`, `IFERROR`, `NA()` |
| Backtest | class-level WAPE and bias, best method | `SUMIFS` with 2 criteria, `INDEX/MATCH` with `MIN`, `SUBSTITUTE` |
| Policy | safety stock, ROP, EOQ, status for 150 products | `SUMIFS` with 3 criteria (lead-time demand), `ROUNDUP`, `SQRT`, `NORM.S.DIST`, conditional formatting |
| Summary | KPIs, class tables, trade-off, top-10 reorder list | `SUMPRODUCT`, `COUNTIFS` with wildcards (`"A*"`, `"?Z"`), `LARGE` + `INDEX/MATCH` |
| Charts | forecast vs actual for the selected product, trade-off curve | charts linked to the sheets |

Checks built in: the Forecast sheet shows "✓ same" when its numbers match the Python batch run, and ABC_XYZ counts how many
classes agree with SQL/Python (150/150 at the default limits).

**Things to try live:** service level 98% (recommended stock rises to £297.9k, so the saving disappears: that's the trade-off);
lead time 4 weeks (49 products to reorder); A = 98% and C = 90% (stock moves towards the valuable products).

---

## 10. SQL (`sql/`)

Run order: `01` creates and loads the tables, `02`–`03` build the weekly demand and ABC–XYZ tables, `04`–`07` answer the questions.
Every query has a one-line comment saying which business question it answers.

Window functions used, and where:

| Function | Query | What it does there |
|---|---|---|
| `WITH RECURSIVE` | WD1 | generates the expected list of 103 weeks to check the calendar |
| `ROW_NUMBER` | WD3, FC4 | picks the top 150 products; picks the best method per class |
| `SUM() OVER (ORDER BY … ROWS UNBOUNDED PRECEDING)` | AB1 | running share of value for ABC |
| `PERCENT_RANK`, `NTILE(5)` | AB1, AB5, AB6 | value percentile and value quintiles |
| `RANK … PARTITION BY` | AB7 | most erratic products within each ABC class |
| `AVG() OVER (ROWS BETWEEN 3 PRECEDING …)` | WD7, DP1 | 4-week and 13-week rolling averages |
| `LAG`, `LEAD` | DP1, DP2, DP6, BI5 | week-on-week change, same week last year (`LAG(x, 52)`), next week |
| Gaps-and-islands | DP5 | longest run of zero-demand weeks |
| `STDDEV_SAMP` | AB1 | variability for CV and safety stock |

`scripts/run_sql_tests.py` runs every query with DuckDB (no MySQL server needed) and checks that the tables SQL builds match the
Python ones exactly: same weekly demand, same 150 products, same ABC–XYZ classes, same best method per class.

---

## 11. Power BI (`powerbi/`)

Four pages: Inventory Overview, ABC-XYZ Matrix, Forecast vs Actual, Reorder & At-risk. Two what-if slicers (service level,
lead time) drive every policy measure through `SUMX` over the products (see [powerbi/README.md](../powerbi/README.md)).
The numbers match Excel and SQL exactly at the default assumptions.

---

## 12. Limitations (say them before you're asked)

1. **Assumed costs, lead time and current stock.** The impact numbers depend on them; the method doesn't. All are inputs.
2. **Sales, not demand.** Weeks with zero sales may have been stock-outs.
3. **One season of history.** Only one Christmas before the test period, so Holt-Winters can't learn how the pattern changes.
4. **Some choices were made after seeing test results** (the 9-week smoothing, the moving-average window). Strictly they should be
   chosen on a separate validation period.
5. **Simple policy model.** Fixed lead time, continuous review, normal demand. Real life has lead-time variability, supplier minimum
   order quantities, case packs and shelf-space limits.

**What I'd do next:** use the forecast error (RMSE) for safety stock, add lead-time variability, use a separate validation period,
and try Croston's method for the lumpiest products.
