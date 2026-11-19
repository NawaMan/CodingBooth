-- Sales Explorer: Demo database seed
-- Idempotent — safe to run multiple times

-- Create sales table if not exists
CREATE TABLE IF NOT EXISTS sales (
    id           SERIAL PRIMARY KEY,
    sale_date    DATE         NOT NULL,
    category     TEXT         NOT NULL,
    product      TEXT         NOT NULL,
    region       TEXT         NOT NULL,
    quantity     INTEGER      NOT NULL,
    unit_price   NUMERIC(10,2) NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL
);

-- Only seed if table is empty
INSERT INTO sales (sale_date, category, product, region, quantity, unit_price, total_amount)
SELECT * FROM (VALUES
    -- Electronics
    ('2025-01-10'::date, 'Electronics', 'Laptop',        'North America',  2,  999.99, 1999.98),
    ('2025-01-22'::date, 'Electronics', 'Smartphone',    'Europe',         5,  699.99, 3499.95),
    ('2025-02-05'::date, 'Electronics', 'Tablet',        'Asia',           8,  449.99, 3599.92),
    ('2025-02-18'::date, 'Electronics', 'Laptop',        'Europe',         1, 1299.99, 1299.99),
    ('2025-03-02'::date, 'Electronics', 'Headphones',    'North America',  15, 199.99, 2999.85),
    ('2025-03-20'::date, 'Electronics', 'Smartphone',    'South America',  3,  599.99, 1799.97),
    ('2025-04-11'::date, 'Electronics', 'Tablet',        'North America',  6,  449.99, 2699.94),
    ('2025-05-07'::date, 'Electronics', 'Laptop',        'Asia',           4, 1099.99, 4399.96),
    ('2025-06-15'::date, 'Electronics', 'Headphones',    'Europe',         20, 149.99, 2999.80),
    ('2025-07-22'::date, 'Electronics', 'Smartphone',    'North America',  7,  799.99, 5599.93),

    -- Clothing
    ('2025-01-15'::date, 'Clothing',    'T-Shirt',       'North America', 25,   29.99,  749.75),
    ('2025-02-10'::date, 'Clothing',    'Jeans',         'Europe',        12,   59.99,  719.88),
    ('2025-03-05'::date, 'Clothing',    'Jacket',        'North America',  5,  129.99,  649.95),
    ('2025-03-28'::date, 'Clothing',    'Sneakers',      'Asia',          18,   89.99, 1619.82),
    ('2025-04-20'::date, 'Clothing',    'T-Shirt',       'South America', 30,   24.99,  749.70),
    ('2025-05-15'::date, 'Clothing',    'Jeans',         'North America', 10,   69.99,  699.90),
    ('2025-06-08'::date, 'Clothing',    'Jacket',        'Europe',         3,  149.99,  449.97),
    ('2025-07-12'::date, 'Clothing',    'Sneakers',      'North America', 14,   99.99, 1399.86),
    ('2025-08-25'::date, 'Clothing',    'T-Shirt',       'Asia',          40,   19.99,  799.60),

    -- Food & Beverage
    ('2025-01-08'::date, 'Food & Beverage', 'Coffee Beans',   'South America', 50,  14.99,  749.50),
    ('2025-02-14'::date, 'Food & Beverage', 'Olive Oil',      'Europe',        30,  12.99,  389.70),
    ('2025-03-10'::date, 'Food & Beverage', 'Green Tea',      'Asia',          60,   9.99,  599.40),
    ('2025-04-05'::date, 'Food & Beverage', 'Coffee Beans',   'North America', 35,  16.99,  594.65),
    ('2025-05-20'::date, 'Food & Beverage', 'Chocolate',      'Europe',        45,   7.99,  359.55),
    ('2025-06-18'::date, 'Food & Beverage', 'Olive Oil',      'North America', 20,  14.99,  299.80),
    ('2025-07-30'::date, 'Food & Beverage', 'Green Tea',      'Asia',          80,   8.99,  719.20),
    ('2025-08-12'::date, 'Food & Beverage', 'Chocolate',      'South America', 55,   6.99,  384.45),
    ('2025-09-05'::date, 'Food & Beverage', 'Coffee Beans',   'Europe',        40,  15.99,  639.60),

    -- Home & Garden
    ('2025-02-01'::date, 'Home & Garden', 'Desk Lamp',      'North America', 10,  45.99,  459.90),
    ('2025-03-15'::date, 'Home & Garden', 'Plant Pot',       'Europe',        25,  19.99,  499.75),
    ('2025-04-22'::date, 'Home & Garden', 'Tool Set',        'North America',  8,  79.99,  639.92),
    ('2025-05-10'::date, 'Home & Garden', 'Desk Lamp',       'Asia',          15,  39.99,  599.85),
    ('2025-06-28'::date, 'Home & Garden', 'Garden Hose',     'South America', 12,  34.99,  419.88),
    ('2025-07-05'::date, 'Home & Garden', 'Plant Pot',       'North America', 20,  24.99,  499.80),
    ('2025-08-18'::date, 'Home & Garden', 'Tool Set',        'Europe',         6,  89.99,  539.94),

    -- Books & Media
    ('2025-01-20'::date, 'Books & Media', 'Novel',           'North America', 30,  14.99,  449.70),
    ('2025-02-28'::date, 'Books & Media', 'Textbook',        'Europe',        10,  49.99,  499.90),
    ('2025-04-08'::date, 'Books & Media', 'Audiobook',       'North America', 20,  19.99,  399.80),
    ('2025-05-30'::date, 'Books & Media', 'Novel',           'Asia',          35,  12.99,  454.65),
    ('2025-06-22'::date, 'Books & Media', 'Textbook',        'South America',  8,  39.99,  319.92),
    ('2025-07-15'::date, 'Books & Media', 'Audiobook',       'Europe',        25,  17.99,  449.75),
    ('2025-08-05'::date, 'Books & Media', 'Novel',           'North America', 40,  13.99,  559.60),
    ('2025-09-10'::date, 'Books & Media', 'Textbook',        'Asia',          12,  44.99,  539.88),

    -- Extra month coverage
    ('2025-09-20'::date, 'Electronics',    'Laptop',        'Europe',         3, 1199.99, 3599.97),
    ('2025-10-05'::date, 'Clothing',       'Jacket',        'North America',  7,  139.99,  979.93),
    ('2025-10-18'::date, 'Food & Beverage','Chocolate',     'Asia',          65,   8.49,  551.85),
    ('2025-11-02'::date, 'Home & Garden',  'Desk Lamp',     'Europe',        12,  49.99,  599.88),
    ('2025-11-15'::date, 'Books & Media',  'Audiobook',     'North America', 18,  21.99,  395.82),
    ('2025-12-01'::date, 'Electronics',    'Smartphone',    'Asia',          10,  749.99, 7499.90),
    ('2025-12-20'::date, 'Clothing',       'Sneakers',      'Europe',        22,  109.99, 2419.78)
) AS seed(sale_date, category, product, region, quantity, unit_price, total_amount)
WHERE NOT EXISTS (SELECT 1 FROM sales LIMIT 1);
