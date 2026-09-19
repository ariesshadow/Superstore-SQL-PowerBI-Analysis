CREATE TABLE raw_orders (
    row_id TEXT,
    order_id TEXT,
    order_date TEXT,
    ship_date TEXT,
    ship_mode TEXT,
    customer_id TEXT,
    customer_name TEXT,
    segment TEXT,
    country_region TEXT,
    city TEXT,
    state_province TEXT,
    postal_code TEXT,
    region TEXT,
    product_id TEXT,
    category TEXT,
    sub_category TEXT,
    product_name TEXT,
    sales TEXT,
    quantity TEXT,
    discount TEXT,
    profit TEXT
);

CREATE TABLE raw_people (
    regional_manager TEXT,
    region TEXT
);

CREATE TABLE raw_returns (
    order_id TEXT,
    returned TEXT
);

-- Checking total record counts across all three tables
SELECT 'orders' AS table_name, COUNT(*) AS record_count FROM raw_orders
UNION ALL
SELECT 'people' AS table_name, COUNT(*) AS record_count FROM raw_people
UNION ALL
SELECT 'returns' AS table_name, COUNT(*) AS record_count FROM raw_returns;

-- ===============================================================
-- Uncovering NULLs, negative values, and duplicates
-- ===============================================================

-- 1. Checking for unexpected NULL values in critical columns
SELECT 
    COUNT(*) FILTER (WHERE row_id IS NULL) AS null_row_ids,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS null_order_ids,
    COUNT(*) FILTER (WHERE order_date IS NULL) AS null_order_dates,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS null_customer_ids,
    COUNT(*) FILTER (WHERE postal_code IS NULL) AS null_postal_codes,
    COUNT(*) FILTER (WHERE sales IS NULL) AS null_sales
FROM raw_orders;

-- 2. Checking for logical anomalies (with explicit type casting)
SELECT 
    COUNT(*) FILTER (WHERE sales::numeric <= 0) AS non_positive_sales,
    COUNT(*) FILTER (WHERE quantity::integer <= 0) AS non_positive_quantity,
    COUNT(*) FILTER (WHERE ship_date::date < order_date::date) AS invalid_ship_dates
FROM raw_orders;

-- 3. Checking for exact row duplication (excluding primary key row_id)
SELECT order_id, product_id, customer_id, COUNT(*) AS duplicate_count
FROM raw_orders
GROUP BY order_id, product_id, customer_id
HAVING COUNT(*) > 1;

-- Inspecting full details of a duplicate transaction
SELECT row_id, order_id, customer_id, product_id, sales, quantity, discount, profit
FROM raw_orders
WHERE order_id = 'US-2026-152912' 
  AND product_id = 'OFF-ST-10003208';

  -- Converting text fields to native SQL numeric and date data types
ALTER TABLE raw_orders 
    ALTER COLUMN sales TYPE NUMERIC USING sales::numeric,
    ALTER COLUMN quantity TYPE INTEGER USING quantity::integer,
    ALTER COLUMN discount TYPE NUMERIC(5,2) USING discount::numeric,
    ALTER COLUMN profit TYPE NUMERIC USING profit::numeric,
    ALTER COLUMN order_date TYPE DATE USING order_date::date,
    ALTER COLUMN ship_date TYPE DATE USING ship_date::date;

	-- Creating clean production view for orders
CREATE VIEW orders AS 
SELECT * FROM raw_orders;

-- Creating clean production view for people
CREATE VIEW people AS 
SELECT * FROM raw_people;

-- Creating clean production view for returns
CREATE VIEW returns AS 
SELECT * FROM raw_returns;

-- Executive KPI Summary
SELECT 
    ROUND(SUM(sales), 2) AS total_revenue,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND((SUM(profit) / SUM(sales)) * 100, 2) AS profit_margin_pct,
    SUM(quantity) AS total_units_sold,
    COUNT(DISTINCT order_id) AS total_unique_orders
FROM orders; 

-- Category & Sub-Category Breakdown
SELECT 
    category,
    sub_category,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND((SUM(profit) / NULLIF(SUM(sales), 0)) * 100, 2) AS profit_margin_pct,
    SUM(quantity) AS units_sold
FROM orders
GROUP BY category, sub_category
ORDER BY total_profit ASC; -- Ascending to highlight losing/low-margin products first

-- Regional and Managerial Performance Breakdown
SELECT 
    p.regional_manager,
    o.region,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(o.sales), 2) AS total_sales,
    ROUND(SUM(o.profit), 2) AS total_profit,
    ROUND((SUM(o.profit) / NULLIF(SUM(o.sales), 0)) * 100, 2) AS profit_margin_pct
FROM orders o
JOIN people p ON o.region = p.region
GROUP BY p.regional_manager, o.region
ORDER BY total_profit DESC;

-- Impact of Discount Tiers on Profitability
SELECT 
    CASE 
        WHEN discount = 0 THEN '01 - No Discount (0%)'
        WHEN discount > 0 AND discount <= 0.20 THEN '02 - Low Discount (1% - 20%)'
        WHEN discount > 0.20 AND discount <= 0.50 THEN '03 - Moderate Discount (21% - 50%)'
        ELSE '04 - Heavy Discount (> 50%)'
    END AS discount_tier,
    COUNT(*) AS total_line_items,
    ROUND(SUM(sales), 2) AS total_sales,
    ROUND(SUM(profit), 2) AS total_profit,
    ROUND((SUM(profit) / NULLIF(SUM(sales), 0)) * 100, 2) AS profit_margin_pct
FROM orders
GROUP BY 
    CASE 
        WHEN discount = 0 THEN '01 - No Discount (0%)'
        WHEN discount > 0 AND discount <= 0.20 THEN '02 - Low Discount (1% - 20%)'
        WHEN discount > 0.20 AND discount <= 0.50 THEN '03 - Moderate Discount (21% - 50%)'
        ELSE '04 - Heavy Discount (> 50%)'
    END
ORDER BY discount_tier;

-- Analysis of Returned Orders and Lost Revenue/Profit
SELECT 
    COALESCE(r.returned, 'No') AS is_returned,
    COUNT(DISTINCT o.order_id) AS order_count,
    ROUND(SUM(o.sales), 2) AS total_sales,
    ROUND(SUM(o.profit), 2) AS total_profit
FROM orders o
LEFT JOIN raw_returns r ON o.order_id = r.order_id
GROUP BY COALESCE(r.returned, 'No');

