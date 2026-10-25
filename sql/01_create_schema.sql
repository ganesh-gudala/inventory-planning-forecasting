/* =====================================================================
   Inventory planning & demand forecasting  ·  UK online gift retailer (UCI Online Retail II)
   01 · Create tables and load the CSVs  (MySQL 8.0)

   order_lines    clean invoice lines from notebook 01 (same cleaning rules as the returns project).
                  line_type = 'Sale' or 'Return'; returns have a negative quantity.
   weeks          the planning calendar: week 1 = Mon 07-Dec-2009 ... week 103 = Mon 21-Nov-2011,
                  then 12 future weeks. period = 'Train' (1-91), 'Test' (92-103), 'Future' (104-115)
   model_params   per SKU: fitted smoothing parameters and the forecast method chosen for its class
   forecasts      backtest and future forecasts from notebook 02 (all four methods, 12 weeks each)

   The weekly demand table and the ABC-XYZ classes are BUILT here in SQL (files 02 and 03),
   then checked against the Python versions by scripts/run_sql_tests.py.

   Run from the repo root:  mysql --local-infile=1 -u <user> -p < sql/01_create_schema.sql
   ===================================================================== */

CREATE DATABASE IF NOT EXISTS inventory_planning;
USE inventory_planning;

DROP TABLE IF EXISTS order_lines;
DROP TABLE IF EXISTS weeks;
DROP TABLE IF EXISTS model_params;
DROP TABLE IF EXISTS forecasts;

CREATE TABLE order_lines (
    invoice_no    VARCHAR(10)   NOT NULL,
    invoice_date  DATE          NOT NULL,
    line_type     VARCHAR(10)   NOT NULL,
    stock_code    VARCHAR(12)   NOT NULL,
    quantity      INT           NOT NULL,
    unit_price    DECIMAL(10,3) NOT NULL,
    line_value    DECIMAL(12,2) NOT NULL,
    customer_id   VARCHAR(10)   NOT NULL,
    country       VARCHAR(40)   NOT NULL,
    INDEX ix_lines_date (invoice_date),
    INDEX ix_lines_product (stock_code)
);

CREATE TABLE weeks (
    week_no     INT PRIMARY KEY,
    week_start  DATE        NOT NULL,
    period      VARCHAR(6)  NOT NULL,
    in_last_52  VARCHAR(5)  NOT NULL,
    year        INT         NOT NULL,
    month       CHAR(3)     NOT NULL
);

CREATE TABLE model_params (
    stock_code     VARCHAR(12) PRIMARY KEY,
    ses_alpha      DECIMAL(4,2) NOT NULL,
    hw_alpha       DECIMAL(4,2) NOT NULL,
    hw_beta        DECIMAL(4,2) NOT NULL,
    hw_gamma       DECIMAL(4,2) NOT NULL,
    chosen_method  VARCHAR(20)  NOT NULL
);

CREATE TABLE forecasts (
    stock_code      VARCHAR(12)   NOT NULL,
    run             VARCHAR(8)    NOT NULL,    -- 'Backtest' or 'Future'
    method          VARCHAR(20)   NOT NULL,
    week_no         INT           NOT NULL,
    horizon         INT           NOT NULL,    -- weeks ahead: 1..12
    forecast_units  DECIMAL(12,4) NOT NULL,
    is_chosen       VARCHAR(5)    NOT NULL,
    PRIMARY KEY (stock_code, run, method, week_no)
);

LOAD DATA LOCAL INFILE 'data/processed/order_lines.csv' INTO TABLE order_lines
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES;
LOAD DATA LOCAL INFILE 'data/processed/weeks.csv' INTO TABLE weeks
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES;
LOAD DATA LOCAL INFILE 'data/processed/model_params.csv' INTO TABLE model_params
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES;
LOAD DATA LOCAL INFILE 'data/processed/forecasts.csv' INTO TABLE forecasts
    FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES;
