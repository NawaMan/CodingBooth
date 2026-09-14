-- PostgREST example: seed data for a small product catalog.
-- Demonstrates pg_trgm (fuzzy text search) and pgvector (similarity search),
-- both enabled automatically by postgresql+pg-ext-pkg — no CREATE EXTENSION
-- needed here, it already happened on container boot.
-- Idempotent — safe to run multiple times.

CREATE TABLE IF NOT EXISTS products (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT NOT NULL,
    embedding   vector(3) NOT NULL
);

CREATE INDEX IF NOT EXISTS products_name_trgm_idx ON products USING gin (name gin_trgm_ops);

-- A toy 3-dimensional embedding stands in for a real one (OpenAI/etc. embeddings
-- are hundreds of dimensions) so the numbers stay readable in this demo: axis 1
-- leans "footwear", axis 2 leans "fitness/leisure", axis 3 leans "electronics".
INSERT INTO products (name, description, embedding)
SELECT * FROM (VALUES
    ('Trail Running Shoes', 'Lightweight shoes built for muddy trail runs', '[0.9,0.1,0.0]'::vector),
    ('Road Running Shoes',  'Cushioned shoes for pavement running',         '[0.8,0.3,0.0]'::vector),
    ('Hiking Boots',        'Sturdy waterproof boots for hiking trails',    '[0.7,0.2,0.1]'::vector),
    ('Yoga Mat',            'Non-slip mat for yoga and stretching',         '[0.0,0.9,0.1]'::vector),
    ('Wireless Headphones', 'Noise-cancelling over-ear headphones',         '[0.0,0.0,0.9]'::vector)
) AS v(name, description, embedding)
WHERE NOT EXISTS (SELECT 1 FROM products);

-- Exposed by PostgREST as POST /rpc/match_products — the pgvector-powered
-- "find similar products" query a real app would call with a real embedding.
CREATE OR REPLACE FUNCTION match_products(query_embedding vector(3), match_count int DEFAULT 3)
RETURNS SETOF products
LANGUAGE sql STABLE
AS $$
    SELECT * FROM products ORDER BY embedding <-> query_embedding LIMIT match_count;
$$;

-- Exposed by PostgREST as POST /rpc/search_products — pg_trgm's actual value
-- over a plain ILIKE: ranks by trigram similarity, so a misspelled query
-- ("Runing Shoez") still finds "Running Shoes" and ranks it above unrelated
-- rows, rather than requiring an exact substring match.
CREATE OR REPLACE FUNCTION search_products(query text, min_similarity real DEFAULT 0.1)
RETURNS TABLE(id int, name text, description text, similarity real)
LANGUAGE sql STABLE
AS $$
    SELECT id, name, description, similarity(name, query) AS similarity
    FROM products
    WHERE similarity(name, query) > min_similarity
    ORDER BY similarity DESC;
$$;

-- PostgREST caches the schema at startup (it was already running before this
-- table/function existed) and only re-reads it on this notification — without
-- it, every request below 404s with "Could not find the table/function ...
-- in the schema cache" even though psql can see it fine.
NOTIFY pgrst, 'reload schema';
