// Sales Explorer — Express server with Chart.js UI
// Queries PostgreSQL sales data with user-defined filters

const express = require('express');
const { Pool } = require('pg');

const app = express();
const PORT = process.env.PORT || 13000;

const pool = new Pool({
    host: process.env.PGHOST || 'localhost',
    port: process.env.PGPORT || 5432,
    database: process.env.PGDATABASE || 'demo',
    user: process.env.PGUSER || 'coder',
    password: process.env.PGPASSWORD || '',
});

// --- API: distinct filter values ---
app.get('/api/filters', async (_req, res) => {
    try {
        const [cats, regions, products] = await Promise.all([
            pool.query('SELECT DISTINCT category FROM sales ORDER BY category'),
            pool.query('SELECT DISTINCT region   FROM sales ORDER BY region'),
            pool.query('SELECT DISTINCT product  FROM sales ORDER BY product'),
        ]);
        res.json({
            categories: cats.rows.map(r => r.category),
            regions: regions.rows.map(r => r.region),
            products: products.rows.map(r => r.product),
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// --- API: filtered sales data ---
app.get('/api/sales', async (req, res) => {
    try {
        const { category, region, product, from, to } = req.query;
        const conditions = [];
        const params = [];
        let idx = 1;

        if (category) { conditions.push(`category = $${idx++}`); params.push(category); }
        if (region) { conditions.push(`region   = $${idx++}`); params.push(region); }
        if (product) { conditions.push(`product  = $${idx++}`); params.push(product); }
        if (from) { conditions.push(`sale_date >= $${idx++}`); params.push(from); }
        if (to) { conditions.push(`sale_date <= $${idx++}`); params.push(to); }

        const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
        const sql = `SELECT * FROM sales ${where} ORDER BY sale_date`;
        const { rows } = await pool.query(sql, params);
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// --- API: aggregated data for charting ---
app.get('/api/sales/summary', async (req, res) => {
    try {
        const { category, region, product, from, to, group_by } = req.query;
        const conditions = [];
        const params = [];
        let idx = 1;

        if (category) { conditions.push(`category = $${idx++}`); params.push(category); }
        if (region) { conditions.push(`region   = $${idx++}`); params.push(region); }
        if (product) { conditions.push(`product  = $${idx++}`); params.push(product); }
        if (from) { conditions.push(`sale_date >= $${idx++}`); params.push(from); }
        if (to) { conditions.push(`sale_date <= $${idx++}`); params.push(to); }

        const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
        const groupCol = ['category', 'region', 'product'].includes(group_by) ? group_by : 'category';

        const sql = `
      SELECT ${groupCol}                   AS label,
             SUM(total_amount)::numeric    AS total_revenue,
             SUM(quantity)::int            AS total_quantity,
             COUNT(*)::int                 AS num_transactions
      FROM sales ${where}
      GROUP BY ${groupCol}
      ORDER BY total_revenue DESC
    `;
        const { rows } = await pool.query(sql, params);
        res.json(rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// --- UI: inline HTML with Chart.js ---
const HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Sales Explorer</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<style>
  :root {
    --bg:      #0f172a;
    --surface: #1e293b;
    --border:  #334155;
    --text:    #e2e8f0;
    --muted:   #94a3b8;
    --accent:  #38bdf8;
    --accent2: #818cf8;
    --green:   #34d399;
    --orange:  #fb923c;
    --pink:    #f472b6;
  }
  * { margin:0; padding:0; box-sizing:border-box; }
  body {
    font-family: 'Inter', 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: var(--bg);
    color: var(--text);
    min-height: 100vh;
  }
  header {
    background: linear-gradient(135deg, #1e293b 0%, #0f172a 100%);
    border-bottom: 1px solid var(--border);
    padding: 1.5rem 2rem;
    display: flex;
    align-items: center;
    gap: 1rem;
  }
  header h1 {
    font-size: 1.5rem;
    font-weight: 700;
    background: linear-gradient(135deg, var(--accent), var(--accent2));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  header .badge {
    font-size: 0.7rem;
    background: var(--accent);
    color: var(--bg);
    padding: 0.2rem 0.6rem;
    border-radius: 9999px;
    font-weight: 600;
    letter-spacing: 0.05em;
  }
  .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
  .filters {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 1rem;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 1.5rem;
    margin-bottom: 1.5rem;
  }
  .filter-group { display: flex; flex-direction: column; gap: 0.4rem; }
  .filter-group label {
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--muted);
    font-weight: 600;
  }
  select, input[type="date"] {
    background: var(--bg);
    border: 1px solid var(--border);
    color: var(--text);
    padding: 0.55rem 0.75rem;
    border-radius: 8px;
    font-size: 0.875rem;
    transition: border-color 0.2s;
  }
  select:focus, input:focus {
    outline: none;
    border-color: var(--accent);
    box-shadow: 0 0 0 3px rgba(56,189,248,0.15);
  }
  .btn-row {
    display: flex;
    gap: 0.75rem;
    align-items: end;
  }
  button {
    cursor: pointer;
    border: none;
    border-radius: 8px;
    padding: 0.55rem 1.5rem;
    font-size: 0.875rem;
    font-weight: 600;
    transition: all 0.2s;
  }
  .btn-primary {
    background: linear-gradient(135deg, var(--accent), var(--accent2));
    color: var(--bg);
  }
  .btn-primary:hover { opacity: 0.9; transform: translateY(-1px); }
  .btn-secondary {
    background: var(--border);
    color: var(--text);
  }
  .btn-secondary:hover { background: #475569; }
  .charts {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1.5rem;
    margin-bottom: 1.5rem;
  }
  @media (max-width: 800px) { .charts { grid-template-columns: 1fr; } }
  .chart-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 1.5rem;
  }
  .chart-card h3 {
    font-size: 0.875rem;
    color: var(--muted);
    margin-bottom: 1rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 1rem;
    margin-bottom: 1.5rem;
  }
  .stat-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 1.25rem;
    text-align: center;
  }
  .stat-card .value {
    font-size: 1.75rem;
    font-weight: 700;
    background: linear-gradient(135deg, var(--accent), var(--green));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .stat-card .label {
    font-size: 0.75rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    margin-top: 0.3rem;
  }
  .table-wrap {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    overflow: hidden;
  }
  .table-header {
    display: flex; justify-content: space-between; align-items: center;
    padding: 1rem 1.5rem;
    border-bottom: 1px solid var(--border);
  }
  .table-header h3 {
    font-size: 0.875rem; color: var(--muted);
    text-transform: uppercase; letter-spacing: 0.05em;
  }
  .table-header .count {
    font-size: 0.8rem; color: var(--accent);
  }
  table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
  thead th {
    text-align: left; padding: 0.75rem 1rem;
    border-bottom: 1px solid var(--border);
    color: var(--muted); font-weight: 600;
    font-size: 0.75rem; text-transform: uppercase;
    letter-spacing: 0.08em;
  }
  tbody td { padding: 0.65rem 1rem; border-bottom: 1px solid #1e293b; }
  tbody tr:hover { background: rgba(56,189,248,0.04); }
  .tag {
    display: inline-block; padding: 0.15rem 0.5rem;
    border-radius: 6px; font-size: 0.75rem; font-weight: 500;
  }
  .tag-electronics { background: rgba(56,189,248,0.15); color: var(--accent); }
  .tag-clothing    { background: rgba(244,114,182,0.15); color: var(--pink); }
  .tag-food        { background: rgba(52,211,153,0.15);  color: var(--green); }
  .tag-home        { background: rgba(251,146,60,0.15);  color: var(--orange); }
  .tag-books       { background: rgba(129,140,248,0.15); color: var(--accent2); }
  .where-display {
    font-family: 'Fira Code', 'Consolas', monospace;
    font-size: 0.8rem;
    color: var(--muted);
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 0.75rem 1rem;
    margin-bottom: 1.5rem;
    word-break: break-all;
  }
  .where-display .keyword { color: var(--accent); font-weight: 600; }
  .where-display .value   { color: var(--green); }
  .loading {
    text-align: center; padding: 3rem; color: var(--muted);
    font-size: 0.9rem;
  }
</style>
</head>
<body>
<header>
  <h1>📊 Sales Explorer</h1>
  <span class="badge">DEMO</span>
</header>
<div class="container">
  <div class="filters" id="filters">
    <div class="filter-group">
      <label>Category</label>
      <select id="f-category"><option value="">All Categories</option></select>
    </div>
    <div class="filter-group">
      <label>Region</label>
      <select id="f-region"><option value="">All Regions</option></select>
    </div>
    <div class="filter-group">
      <label>Product</label>
      <select id="f-product"><option value="">All Products</option></select>
    </div>
    <div class="filter-group">
      <label>From</label>
      <input type="date" id="f-from" value="2025-01-01">
    </div>
    <div class="filter-group">
      <label>To</label>
      <input type="date" id="f-to" value="2025-12-31">
    </div>
    <div class="filter-group">
      <label>Group By</label>
      <select id="f-groupby">
        <option value="category">Category</option>
        <option value="region">Region</option>
        <option value="product">Product</option>
      </select>
    </div>
    <div class="filter-group btn-row">
      <button class="btn-primary" onclick="query()">🔍 Query</button>
      <button class="btn-secondary" onclick="resetFilters()">↺ Reset</button>
    </div>
  </div>

  <div class="where-display" id="where-display">
    <span class="keyword">SELECT</span> * <span class="keyword">FROM</span> sales
  </div>

  <div class="stats" id="stats">
    <div class="stat-card"><div class="value" id="s-revenue">—</div><div class="label">Total Revenue</div></div>
    <div class="stat-card"><div class="value" id="s-qty">—</div><div class="label">Items Sold</div></div>
    <div class="stat-card"><div class="value" id="s-txn">—</div><div class="label">Transactions</div></div>
    <div class="stat-card"><div class="value" id="s-avg">—</div><div class="label">Avg Order</div></div>
  </div>

  <div class="charts">
    <div class="chart-card">
      <h3>Revenue by Group</h3>
      <canvas id="chart-revenue"></canvas>
    </div>
    <div class="chart-card">
      <h3>Quantity by Group</h3>
      <canvas id="chart-qty"></canvas>
    </div>
  </div>

  <div class="table-wrap">
    <div class="table-header">
      <h3>Sales Records</h3>
      <span class="count" id="row-count"></span>
    </div>
    <table>
      <thead>
        <tr>
          <th>Date</th><th>Category</th><th>Product</th>
          <th>Region</th><th>Qty</th><th>Unit Price</th><th>Total</th>
        </tr>
      </thead>
      <tbody id="tbody"></tbody>
    </table>
  </div>
</div>
<script>
const COLORS = ['#38bdf8','#f472b6','#34d399','#fb923c','#818cf8','#facc15','#e879f9','#22d3ee'];
const CAT_TAG = {
  'Electronics':     'tag-electronics',
  'Clothing':        'tag-clothing',
  'Food & Beverage': 'tag-food',
  'Home & Garden':   'tag-home',
  'Books & Media':   'tag-books',
};
let chartRev, chartQty;

async function loadFilters() {
  try {
    const res = await fetch('/api/filters');
    const data = await res.json();
    fillSelect('f-category', data.categories);
    fillSelect('f-region',   data.regions);
    fillSelect('f-product',  data.products);
  } catch(e) { console.error('Failed to load filters:', e); }
}

function fillSelect(id, items) {
  const sel = document.getElementById(id);
  items.forEach(v => {
    const o = document.createElement('option');
    o.value = v; o.textContent = v;
    sel.appendChild(o);
  });
}

function buildParams() {
  const p = {};
  const cat = document.getElementById('f-category').value;
  const reg = document.getElementById('f-region').value;
  const prod = document.getElementById('f-product').value;
  const from = document.getElementById('f-from').value;
  const to   = document.getElementById('f-to').value;
  const gb   = document.getElementById('f-groupby').value;
  if (cat)  p.category = cat;
  if (reg)  p.region   = reg;
  if (prod) p.product  = prod;
  if (from) p.from     = from;
  if (to)   p.to       = to;
  p.group_by = gb;
  return p;
}

function buildWhereDisplay(params) {
  const el = document.getElementById('where-display');
  let sql = '<span class="keyword">SELECT</span> * <span class="keyword">FROM</span> sales';
  const clauses = [];
  if (params.category) clauses.push('category = <span class="value">\\'' + params.category + '\\'</span>');
  if (params.region)   clauses.push('region = <span class="value">\\'' + params.region + '\\'</span>');
  if (params.product)  clauses.push('product = <span class="value">\\'' + params.product + '\\'</span>');
  if (params.from)     clauses.push('sale_date >= <span class="value">\\'' + params.from + '\\'</span>');
  if (params.to)       clauses.push('sale_date <= <span class="value">\\'' + params.to + '\\'</span>');
  if (clauses.length) sql += ' <span class="keyword">WHERE</span> ' + clauses.join(' <span class="keyword">AND</span> ');
  sql += ' <span class="keyword">ORDER BY</span> sale_date';
  el.innerHTML = sql;
}

async function query() {
  const params = buildParams();
  buildWhereDisplay(params);
  const qs = new URLSearchParams(params).toString();

  try {
    const [salesRes, summaryRes] = await Promise.all([
      fetch('/api/sales?' + qs),
      fetch('/api/sales/summary?' + qs),
    ]);
    const sales   = await salesRes.json();
    const summary = await summaryRes.json();
    renderStats(sales, summary);
    renderCharts(summary);
    renderTable(sales);
  } catch(e) {
    console.error('Query failed:', e);
  }
}

function renderStats(sales, summary) {
  const totalRev = summary.reduce((s, r) => s + parseFloat(r.total_revenue), 0);
  const totalQty = summary.reduce((s, r) => s + r.total_quantity, 0);
  const totalTxn = summary.reduce((s, r) => s + r.num_transactions, 0);
  const avg = totalTxn ? (totalRev / totalTxn) : 0;
  document.getElementById('s-revenue').textContent = '$' + totalRev.toLocaleString('en-US', {minimumFractionDigits:2, maximumFractionDigits:2});
  document.getElementById('s-qty').textContent     = totalQty.toLocaleString();
  document.getElementById('s-txn').textContent     = totalTxn.toLocaleString();
  document.getElementById('s-avg').textContent     = '$' + avg.toLocaleString('en-US', {minimumFractionDigits:2, maximumFractionDigits:2});
}

function renderCharts(summary) {
  const labels = summary.map(r => r.label);
  const revenue = summary.map(r => parseFloat(r.total_revenue));
  const qty     = summary.map(r => r.total_quantity);
  const colors  = labels.map((_, i) => COLORS[i % COLORS.length]);

  if (chartRev) chartRev.destroy();
  if (chartQty) chartQty.destroy();

  const opts = (title) => ({
    responsive: true,
    plugins: {
      legend: { display: false },
      tooltip: {
        backgroundColor: '#1e293b',
        borderColor: '#334155', borderWidth: 1,
        titleColor: '#e2e8f0', bodyColor: '#94a3b8',
        cornerRadius: 8, padding: 12,
      },
    },
    scales: {
      x: { ticks: { color: '#94a3b8', font: { size: 11 } }, grid: { color: '#1e293b' } },
      y: { ticks: { color: '#94a3b8', font: { size: 11 } }, grid: { color: '#1e293b' } },
    },
  });

  chartRev = new Chart(document.getElementById('chart-revenue'), {
    type: 'bar',
    data: { labels, datasets: [{ label: 'Revenue ($)', data: revenue, backgroundColor: colors, borderRadius: 6 }] },
    options: opts(),
  });
  chartQty = new Chart(document.getElementById('chart-qty'), {
    type: 'bar',
    data: { labels, datasets: [{ label: 'Quantity', data: qty, backgroundColor: colors, borderRadius: 6 }] },
    options: opts(),
  });
}

function renderTable(sales) {
  document.getElementById('row-count').textContent = sales.length + ' records';
  const tbody = document.getElementById('tbody');
  tbody.innerHTML = sales.map(r => {
    const tagClass = CAT_TAG[r.category] || '';
    const date = new Date(r.sale_date).toLocaleDateString('en-US', {year:'numeric',month:'short',day:'numeric'});
    return '<tr>'
      + '<td>' + date + '</td>'
      + '<td><span class="tag ' + tagClass + '">' + r.category + '</span></td>'
      + '<td>' + r.product + '</td>'
      + '<td>' + r.region + '</td>'
      + '<td>' + r.quantity + '</td>'
      + '<td>$' + parseFloat(r.unit_price).toFixed(2) + '</td>'
      + '<td>$' + parseFloat(r.total_amount).toLocaleString('en-US',{minimumFractionDigits:2}) + '</td>'
      + '</tr>';
  }).join('');
}

function resetFilters() {
  document.getElementById('f-category').value = '';
  document.getElementById('f-region').value   = '';
  document.getElementById('f-product').value  = '';
  document.getElementById('f-from').value     = '2025-01-01';
  document.getElementById('f-to').value       = '2025-12-31';
  document.getElementById('f-groupby').value  = 'category';
  query();
}

loadFilters();
query();
</script>
</body>
</html>`;

app.get('/', (_req, res) => {
    res.type('html').send(HTML);
});

app.listen(PORT, () => {
    console.log(`Sales Explorer running on http://localhost:${PORT}`);
});
