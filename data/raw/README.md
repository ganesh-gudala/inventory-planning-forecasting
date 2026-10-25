# Raw data (not stored in Git)

Run this from the repo root to download it:

```bash
python scripts/download_data.py
```

It creates `online_retail_II.csv` (~1.07 million rows, ~90 MB).

- **Dataset:** Online Retail II, UCI Machine Learning Repository, https://archive.ics.uci.edu/dataset/502/online+retail+ii
- **Creator:** Daqing Chen (2019)
- **Licence:** CC BY 4.0
- **What it is:** every invoice line of a real UK-based, non-store online retailer that sells giftware, mostly to wholesalers, from 01-Dec-2009 to 09-Dec-2011.

| Column | Meaning |
|---|---|
| Invoice | 6-digit invoice number. Starts with `C` = credit note (cancellation/return). Starts with `A` = bad-debt adjustment |
| StockCode | product code |
| Description | product name |
| Quantity | units on the line (negative on credit notes) |
| InvoiceDate | date and time of the invoice |
| Price | unit price in GBP |
| Customer ID | 5-digit customer number (blank for some orders) |
| Country | customer's country |
