"""
Download the real dataset used in this project and save it as one CSV.

Source : UCI Machine Learning Repository - "Online Retail II" (Chen, 2019)
         https://archive.ics.uci.edu/dataset/502/online+retail+ii
Licence: CC BY 4.0
What it is: every invoice line of a real UK-based online gift retailer, 01-Dec-2009 to 09-Dec-2011.

The file is ~45 MB, so it is not stored in Git. Run this once:

    python scripts/download_data.py

Output: data/raw/online_retail_II.csv  (both Excel sheets stacked, ~1.07 million rows)
"""
import io
import urllib.request
import zipfile
from pathlib import Path

import pandas as pd

URL = "https://archive.ics.uci.edu/static/public/502/online+retail+ii.zip"
RAW = Path(__file__).resolve().parents[1] / "data" / "raw"


def main():
    RAW.mkdir(parents=True, exist_ok=True)
    out = RAW / "online_retail_II.csv"
    if out.exists():
        print(f"Already downloaded: {out}")
        return

    print("Downloading from UCI ...")
    with urllib.request.urlopen(URL) as resp:
        zipped = zipfile.ZipFile(io.BytesIO(resp.read()))

    print("Reading the Excel file (takes 1-2 minutes) ...")
    with zipped.open("online_retail_II.xlsx") as f:
        sheets = pd.read_excel(f, sheet_name=None, dtype={"Invoice": str, "StockCode": str})

    df = pd.concat(sheets.values(), ignore_index=True)
    df.to_csv(out, index=False)
    print(f"Saved {len(df):,} rows to {out}")


if __name__ == "__main__":
    main()
