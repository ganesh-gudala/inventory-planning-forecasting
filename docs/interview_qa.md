# Interview questions and answers

20 questions a UK supply chain analyst or demand planner interviewer is likely to ask about this project, with short answers
in plain English. Learn the ideas, not the words, and answer in your own way.

---

### About the project

**1. Walk me through the project in two minutes.**
The question was how much stock to hold of each product and when to reorder. I used real invoice data from a UK online gift
retailer (the same one as my returns project), built weekly net demand for the top 150 regular products, and classified them with
ABC–XYZ. I backtested four forecasting methods on Sep–Nov 2011, chose the best method per class using WAPE and bias, then calculated
safety stock, reorder points, EOQ and min/max levels at a 95% service level. Against a blanket 8-weeks-of-cover rule, the policy frees
about £24k (8%) of stock, and more importantly moves stock from steady products to erratic ones. Everything is in an Excel model where
you can change the service level, lead time and costs, plus SQL and a Power BI report.

**2. The data has no stock levels, lead times or costs. How can you plan inventory?**
I made clear, adjustable assumptions: a 3-week lead time, 25% holding cost, £50 per order, unit cost at 60% of the selling price,
and current stock at 8 weeks of cover. They're all inputs in Excel and Power BI. The method stays the same with real numbers; only
the £ results change. In a real job I'd get lead times from purchase-order history and costs from finance.

**3. Why weekly buckets, and why did you net off returns?**
Ordering and stock reviews happen weekly, so that's the planning rhythm. Returns come back into stock, so the stock we really need is
for net demand. I set negative weeks (big returns in quiet weeks) to zero, because that's an old sale coming back, not negative demand.

**4. How did you choose the 150 products?**
Top by net sales value in the last 52 weeks, but only products that sold in at least two-thirds of the weeks. New or one-off products
don't have enough history for a backtest; in practice they're planned with judgement or by comparison with similar products.
The 150 are about a third of the retailer's sales.

---

### ABC–XYZ

**5. Explain ABC–XYZ and why it's useful.**
ABC ranks products by value (A = first 80% of sales, B = next 15%, C = last 5%). XYZ ranks them by how predictable demand is,
using the coefficient of variation (X steady, Y variable, Z erratic). Together they give a 9-box: AX products are valuable and easy
to forecast, so keep stock lean; AZ products are valuable but erratic, so they need the most safety stock and attention; CZ products
might be better made to order or delisted. It tells you where to spend planning time.

**6. Why are 95 of your 150 products A-class?**
Because I only planned the top sellers. Across the whole catalogue all 150 would be A. Inside the top 150, value is more evenly spread,
so 63% of products make 80% of value. I kept the standard 80/15/5 split and explained it, rather than moving the thresholds to get a
prettier chart. The limits are inputs in Excel if the business prefers different ones.

**7. Why did you use CV limits of 0.75 and 1.25 instead of 0.5 and 1.0?**
The textbook limits are usually applied to monthly demand. Weekly demand for a single product is much noisier: with 0.5, only 6 products
would be X. I chose limits that split the range into three useful groups and made them adjustable.

---

### Forecasting

**8. Which forecasting methods did you use and why those?**
Naive (as the benchmark), an 8-week moving average, simple exponential smoothing and Holt-Winters for seasonal products. They're
the standard methods in demand planning tools, easy to explain to a buyer, and they can be built in Excel. The point was to test them
fairly and choose, not to use the most complex model.

**9. How did you test the forecasts?**
A backtest: I pretended it was the end of August 2011, fitted each method on the data up to then, forecast the next 12 weeks, and compared
with what actually happened. The test period was the Christmas run-up, the hardest and most important period for this business.

**10. What's the difference between MAPE, WAPE and bias? Which did you use?**
MAPE averages the percentage error of each week; it breaks when actual demand is zero and over-weights small weeks. WAPE divides total
absolute error by total demand, so it handles zero weeks and focuses on the big weeks; it was my main measure. Bias shows whether the
forecast is consistently too high or too low. I chose methods on WAPE + |bias| because for stock, a consistent under-forecast is what causes
stock-outs.

**11. Your WAPE is around 60%. Isn't that bad?**
For weekly demand of single products at a wholesaler, it's normal: shops order in lumps, so individual weeks jump around a lot. That's
exactly why we hold safety stock. More useful findings: the flat methods were 20–35% too low over the Christmas run-up, while the chosen
methods were only 4% high in total, and forecasts aggregate well (the weekly total of all 150 products tracked actual demand closely).

**12. Why did you choose a method per class rather than per product?**
Twelve test weeks is a short sample, so the "best" method for one product is often luck. Pooling the products in a class gives a more
reliable choice and a simpler process to maintain. Holt-Winters won in the variable, valuable classes (AY, AZ, BY, BZ); smooth methods won
for steady products and for small erratic ones.

**13. Excel's FORECAST.ETS is Holt-Winters too. Why not just use that?**
I included it for comparison. It chooses its own parameters and it wasn't consistently better: on 85123A it had a small bias but a higher
WAPE than my Holt-Winters, and on 22423 its WAPE was 95% against 26–51% for the other methods, because it copied last year's spikes.
Built-in functions still need testing; the backtest is what decides.

---

### Inventory policy

**14. How do you calculate safety stock? Why the square root of lead time?**
Safety stock = z × standard deviation of weekly demand × √(lead time in weeks), with z = NORM.S.INV(service level), 1.645 for 95%.
The square root is there because random weekly ups and downs partly cancel out over several weeks, so uncertainty grows more slowly
than the lead time itself.

**15. What is the reorder point, and how does it relate to min/max?**
Reorder point = expected demand during the lead time + safety stock. When stock falls to it, you order. I used the forecast for the next
three weeks as the lead-time demand, so seasonal products get a higher reorder point before Christmas. Min = the reorder point,
Max = reorder point + EOQ: when stock hits Min, order back up to Max.

**16. What is EOQ, and what are its limits?**
The order size that balances ordering cost against holding cost: √(2 × annual demand × ordering cost ÷ (holding % × unit cost)).
It assumes steady demand, fixed costs and no quantity discounts. In practice you round it to case packs or supplier minimums and cap it
for seasonal or perishable products. Here it gives order cycles of about 9–13 weeks, which shows the £50 ordering cost assumption matters.

**17. What's the difference between cycle service level and fill rate?**
Cycle service level (what I used) is the chance of not running out during a replenishment cycle. Fill rate is the share of demand served
from stock. They're different: at a 95% cycle service level the fill rate is usually higher, because when you do run out it's only for
part of the demand. Retailers often track fill rate, so I'd convert between them in a real project.

---

### Business impact

**18. What's the business impact, and how confident are you in it?**
At 95% service and a 3-week lead time, recommended stock is £270.9k vs £294.8k under the blanket rule: £23.9k (8%) less working capital
and about £6k a year less holding cost. The exact £ depends on my assumptions, but the direction is robust: the blanket rule holds
£32k too much of steady products and £16k too little of erratic ones. 29 products should be reordered now, 26 of them erratic Z items.
I'd present it as "rebalance stock towards risk", not just "cut stock".

**19. How would you decide which service level to use?**
It's a trade-off: going from 95% to 99% needs about 40% more safety stock, and each extra point costs more than the last. The right level
depends on the margin and the cost of a lost sale or an unhappy customer. I'd differentiate by class, for example 98% for A items and
90% for C items; the Excel model lets you test that, and it shows stock moving towards the valuable products.

---

### Reflection

**20. What are the limitations, and what would you improve?**
The costs, lead time and current stock are assumptions. Sales aren't true demand when stock runs out. There's only one Christmas in the
training data, and a couple of settings (the smoothing window, the moving-average length) were chosen after seeing test results, so
strictly they should be tuned on a separate validation period. Next steps: base safety stock on forecast error (RMSE) instead of demand
variability, add lead-time variability, use a separate validation period, and try Croston's method for the lumpiest products.
