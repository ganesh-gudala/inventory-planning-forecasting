# Glossary

Plain-English definitions of every term used in this project, with the formula and an example from the data
where it helps. Terms are in the order you meet them.

---

## Data and demand

**SKU (stock keeping unit)**
One product as the warehouse sees it, for example `85123A` *White hanging heart t-light holder*. Here a SKU = one stock code.

**Demand**
How many units customers want in a period. We can only see **sales**, so demand here = units sold.
If a product was out of stock, real demand was higher than sales (called *censored demand*). The data has no stock levels, so this can't be corrected.

**Net demand (net of returns)**
Units sold − units returned in the same week. A week where returns are bigger than sales is set to 0, because a negative week isn't real demand.

**Weekly bucket**
All sales from Monday to Sunday added together. Planning is done weekly because orders to suppliers are placed weekly.

**Lead time**
Time from placing an order with the supplier to the stock being available to sell. Assumed 3 weeks here (the data has none).

**Planning range**
The SKUs we actually plan: the top 150 regular sellers by value (34.5% of the retailer's sales in the last 52 weeks).

---

## Classification

**ABC analysis**
Sorts SKUs by **value** (here: net sales £ in the last 52 weeks). A = the SKUs that make the first 80% of value, B = the next 15%, C = the last 5%.
Purpose: spend most planning time on the few SKUs that matter most.

**Pareto principle (80/20 rule)**
A small share of items usually makes most of the value. Across a whole catalogue, often ~20% of SKUs = ~80% of sales.
In our top-150 range value is more even (63% of SKUs make 80%), because the long tail was already left out.

**XYZ analysis**
Sorts SKUs by how **predictable** demand is, using the CV. X = steady, Y = variable, Z = erratic. Here X: CV ≤ 0.75, Y: 0.75–1.25, Z: above 1.25.

**CV (coefficient of variation)**
`CV = standard deviation ÷ average`. A size-free measure of how much demand jumps around.
Example: average 100 units a week, standard deviation 50 → CV 0.5 (a typical week is ~50% away from the average).
A CV lets you compare a 10-a-week product with a 1,000-a-week product.

**Standard deviation (σ, sigma)**
The typical distance of each week from the average. Excel: `STDEV.S` (the sample version, divides by n − 1). SQL: `STDDEV_SAMP`.

**9-box matrix (ABC–XYZ matrix)**
A 3×3 grid of ABC (value) by XYZ (variability). Each box suggests a different way to manage the SKU:
AX = important and easy (lean stock, automate), AZ = important and hard (most safety stock, most attention), CZ = unimportant and hard (make to order or delist).

**Seasonality / Christmas uplift**
A pattern that repeats every year. Uplift = average weekly demand Sep–Nov 2010 ÷ average over the training weeks. 1.3 or more = seasonal.

---

## Forecasting

**Forecast**
An estimate of future demand. Always wrong by some amount; the question is by how much and in which direction.

**Naive forecast**
"Next week will be the same as last week." The simplest benchmark. Any method worth using should beat it.

**Moving average (MA)**
The average of the last *N* weeks (here 8), used as the forecast for every future week. Smooths out noise but reacts slowly.

**Simple exponential smoothing (SES)**
A weighted average where recent weeks count more: `level = α × this week's actual + (1 − α) × last level`.
α (alpha, 0 to 1) controls how fast it reacts: high α = follows recent weeks closely, low α = very smooth. The forecast is flat.

**Holt-Winters (triple exponential smoothing)**
SES plus a **trend** (is demand growing?) and a **seasonal** part (what happened in this week last year?). Three smoothing factors:
α for the level, β (beta) for the trend, γ (gamma) for the season. We use the *additive* version: forecast = level + trend × weeks ahead + seasonal effect.

**FORECAST.ETS**
Excel's built-in exponential smoothing (AAA version of Holt-Winters). It chooses its own parameters. Shown in the Excel model for comparison.

**Training period / test period**
Training (weeks 1–91) = the data the method learns from. Test (weeks 92–103) = data the method has not seen, used to check it.

**Backtest (holdout test)**
Pretend it's an earlier date, forecast a period you already know, and compare with what really happened. Here: forecast Sep–Nov 2011 using data up to August 2011.

**Forecast horizon**
How many weeks ahead the forecast is. Here up to 12 weeks.

**Parameter fitting / grid search**
Trying several values (e.g. α = 0.05, 0.10 … 0.95) and keeping the one with the smallest error on the training data.

---

## Forecast accuracy

**Forecast error**
`error = forecast − actual`. Positive = forecast too high, negative = too low.

**MAPE (mean absolute percentage error)**
The average of `|error| ÷ actual` over the weeks. Easy to explain, but breaks when actual = 0 (dividing by zero) and over-punishes small weeks. Here it is only calculated over weeks with actual > 0.

**WAPE (weighted absolute percentage error)**
`WAPE = Σ|error| ÷ Σ actual`. Total size of the mistakes as a % of total demand. Works with zero weeks and gives big weeks more weight, so it's the main accuracy measure here.
Example: actuals 100, 0, 50; forecasts 80, 10, 60 → |errors| 20 + 10 + 10 = 40, Σactual 150 → WAPE 27%.

**Bias**
`Bias = Σ error ÷ Σ actual`. Is the forecast **consistently** too high or too low? −20% = forecasts are 20% too low on average → stock-outs.
A forecast can have a good WAPE but a bad bias; for inventory, bias is dangerous because the errors don't cancel out.

**Score (WAPE + |bias|)**
The rule used here to pick a method: add the accuracy error and the size of the bias, lowest wins.

**RMSE**
Root mean squared error: punishes big misses more. Mentioned for completeness; not used in this project.

---

## Inventory policy

**Service level (cycle service level)**
The probability of **not** running out of stock during one replenishment cycle (between placing an order and receiving it). 95% = we accept running out in about 1 cycle in 20.
Not the same as **fill rate** (the % of demand units served from stock), which is usually higher.

**z (safety factor, z-score)**
How many standard deviations of protection a service level needs: `z = NORM.S.INV(service level)`.
90% → 1.28, 95% → 1.645, 98% → 2.05, 99% → 2.33. It grows faster and faster as you approach 100%.

**Safety stock (SS)**
Extra stock held to cover demand that is higher than forecast during the lead time.
`SS = z × σ(weekly demand) × √(lead time in weeks)`.
Example: z 1.645, σ 100 units/week, lead time 3 weeks → 1.645 × 100 × 1.73 = 285 units.
The square root is there because ups and downs in different weeks partly cancel each other out.

**Lead-time demand**
The demand expected during the lead time. Here: the sum of the chosen method's forecast for the next 3 weeks.

**Reorder point (ROP)**
The stock level at which you place a new order. `ROP = lead-time demand + safety stock`.
If you order exactly when stock hits the ROP, the safety stock is what protects you while the order is on its way.

**EOQ (economic order quantity)**
The order size that balances ordering cost against holding cost:
`EOQ = √(2 × annual demand × ordering cost ÷ (holding cost % × unit cost))`.
Order bigger → fewer orders but more stock to hold; order smaller → less stock but more orders. EOQ is where the two yearly costs are equal.

**Ordering cost**
Fixed cost each time an order is placed (admin, freight booking, receiving). Assumed £50.

**Holding cost (carrying cost)**
Yearly cost of keeping one £ of stock: money tied up, storage, insurance, damage, obsolescence. Assumed 25% of unit cost per year.

**Unit cost**
What the retailer pays for one unit. The data only has selling prices, so unit cost is assumed to be 60% of the average selling price.

**Min / Max levels**
A simple replenishment rule: when stock falls to **Min** (= the reorder point), order enough to get back to **Max** (= ROP + EOQ).

**Cycle stock**
The part of stock that goes up and down with each order. On average it's EOQ ÷ 2.

**Average stock**
`Average stock = safety stock + EOQ ÷ 2`. This is the stock you hold on average under the policy, and what working capital is based on.

**Weeks of cover**
How many weeks the stock would last at average demand: `stock ÷ average weekly demand`.

**Stock-out**
Running out: demand arrives and there's no stock to sell.

**Stock-out risk (in this project)**
If nothing is ordered now, the probability that demand during the lead time is bigger than current stock:
`1 − NORM.S.DIST((current stock − lead-time demand) ÷ (σ × √lead time))`.

**Overstock**
Holding more than the max level: cash tied up for no service benefit.

**Working capital**
Money tied up in running the business, much of it in stock. Holding less stock **frees** working capital (cash the business can use elsewhere).

**Blanket weeks-of-cover rule**
Holding the same number of weeks of stock for every SKU (here 8). Simple, but it ignores how variable each SKU is: too much for steady items, too little for erratic ones.

**Service level vs cost trade-off**
Higher service levels need more safety stock, and the cost rises steeply near 100%: going from 95% to 99% needs about 40% more safety stock.

**Continuous review vs periodic review**
Continuous: check stock all the time and order when it hits the ROP (the policy used here). Periodic: check every *R* weeks and order up to a target; it needs extra safety stock to cover the review period.
