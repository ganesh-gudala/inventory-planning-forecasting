"""
Runs every query in sql/ without needing a MySQL server, and checks SQL against Python.

The queries are written for MySQL 8. Each one is translated to DuckDB with sqlglot and run on an in-memory
database loaded from data/processed/. File 01 (MySQL table definitions and LOAD DATA) is skipped; the
CREATE TABLE ... AS SELECT statements that build the analysis tables are run.

The run fails if a query errors, a check query finds problems, or the tables SQL builds (weekly demand,
planning SKUs, ABC-XYZ, chosen methods) don't match the ones notebook 01 / 02 produced in Python.

Run:  python scripts/run_sql_tests.py        (add -v to print the first rows of every result)
"""
import re
import sys
from pathlib import Path

import duckdb
import pandas as pd
import sqlglot

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR, DATA = ROOT / "sql", ROOT / "data" / "processed"
VERBOSE = "-v" in sys.argv
TABLES = ["order_lines", "weeks", "model_params", "forecasts"]
TEXT_COLS = {"invoice_no": "VARCHAR", "stock_code": "VARCHAR", "customer_id": "VARCHAR",
             "in_last_52": "VARCHAR", "is_chosen": "VARCHAR"}
# queries whose result must be empty / zero
ZERO_CHECKS = {"FC2": "mismatches", "FC5": "mismatches_vs_python", "IP5": None}


def split_statements(sql: str):
    """Yield (label, statement). The label is the '-- XX1: question' comment above the query."""
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    current, label = [], None
    for line in sql.splitlines():
        m = re.match(r"\s*--\s*([A-Z]+\d+):\s*(.*)", line)
        if m:
            label = f"{m.group(1)} {m.group(2)}".strip()
        current.append(re.sub(r"--.*$", "", line))
        if line.rstrip().endswith(";"):
            stmt = "\n".join(current).strip().rstrip(";")
            if stmt:
                yield label, stmt
            current = []


def main() -> int:
    con = duckdb.connect()
    for t in TABLES:
        path = DATA / f"{t}.csv"
        with open(path, encoding="utf-8") as f:
            header = f.readline().strip().split(",")
        types = {c: v for c, v in TEXT_COLS.items() if c in header}
        options = f", types={types}" if types else ""
        con.execute(f"CREATE TABLE {t} AS SELECT * FROM read_csv('{path.as_posix()}'{options})")

    failures, ran = [], 0
    for path in sorted(SQL_DIR.glob("*.sql")):
        if path.name.startswith("01_"):        # MySQL table definitions and LOAD DATA: the CSVs are loaded above
            continue
        for label, stmt in split_statements(path.read_text(encoding="utf-8")):
            code = (label or "").split(" ")[0]
            try:
                duck = sqlglot.transpile(stmt, read="mysql", write="duckdb")[0]
                if re.match(r"\s*(DROP|CREATE)", stmt, re.I):   # builds a table, nothing to show
                    con.execute(duck)
                    continue
                res = con.execute(duck).fetchdf()
                ran += 1
                status = f"{len(res):>5} rows"
                if code in ZERO_CHECKS:
                    col = ZERO_CHECKS[code]
                    problems = len(res) if col is None else int(res[col].sum())
                    if problems:
                        failures.append((path.name, label, f"{problems} problems"))
                        status += "  <-- CHECK FAILED"
                print(f"  ok  {path.name:<26} {(label or '')[:78]:<78} {status}")
                if VERBOSE:
                    print(res.head(10).to_string(), "\n")
            except Exception as exc:  # noqa: BLE001
                failures.append((path.name, label, str(exc).splitlines()[0]))
                print(f"FAIL  {path.name:<26} {(label or '')[:78]:<78} {exc}")

    failures += reconcile(con)
    print(f"\n{ran} queries run, {len(failures)} failure(s)")
    for f in failures:
        print("   -", *f)
    return 1 if failures else 0


def reconcile(con):
    """Compare the tables SQL built with the CSVs Python wrote."""
    out = []

    def check(name, ok, detail=""):
        print(f"  {'ok' if ok else 'FAIL'}  reconcile {name:<45} {detail}")
        if not ok:
            out.append(("reconcile", name, detail))

    wd_py = pd.read_csv(DATA / "weekly_demand.csv", dtype={"stock_code": str})
    wd_sql = con.execute("SELECT stock_code, week_no, demand_units, units_sold, units_returned FROM weekly_demand").fetchdf()
    m = wd_py.merge(wd_sql, on=["stock_code", "week_no"], suffixes=("_py", "_sql"), how="outer", indicator=True)
    check("weekly demand: same SKU-weeks", (m["_merge"] == "both").all(), f"{len(wd_py):,} py vs {len(wd_sql):,} sql")
    diff = (m.demand_units_py - m.demand_units_sql).abs().max()
    check("weekly demand: same units", diff == 0, f"max difference {diff}")

    sku_py = pd.read_csv(DATA / "sku_list.csv", dtype={"stock_code": str})
    sku_sql = con.execute("SELECT stock_code, abc, xyz, cv, peak_uplift, is_seasonal FROM sku_abc_xyz").fetchdf()
    s = sku_py.merge(sku_sql, on="stock_code", suffixes=("_py", "_sql"))
    check("planning SKUs: same 150", len(s) == 150 == len(sku_sql))
    check("ABC class matches", (s.abc_py == s.abc_sql).all(), f"{(s.abc_py != s.abc_sql).sum()} differ")
    check("XYZ class matches", (s.xyz_py == s.xyz_sql).all(), f"{(s.xyz_py != s.xyz_sql).sum()} differ")
    check("CV matches", (s.cv_py - s.cv_sql).abs().max() < 1e-3, f"max diff {(s.cv_py - s.cv_sql).abs().max():.2e}")
    check("seasonal flag matches", (s.is_seasonal_py.astype(int) == s.is_seasonal_sql).all())

    cls_py = pd.read_csv(DATA / "method_by_class.csv").query("is_best")[["abc_xyz", "method"]]
    cls_sql = con.execute("SELECT abc_xyz, method FROM method_by_class_sql WHERE method_rank = 1").fetchdf()
    c = cls_py.merge(cls_sql, on="abc_xyz", suffixes=("_py", "_sql"))
    check("best method per class matches", len(c) == 9 and (c.method_py == c.method_sql).all())
    return out


if __name__ == "__main__":
    sys.exit(main())
