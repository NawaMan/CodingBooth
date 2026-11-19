import express from 'express'
import cors from 'cors'
import pg from 'pg'

const PORT = 3000
const user = process.env.USER || 'coder'

const pool = new pg.Pool({
  host: '/var/run/postgresql',
  user,
  database: user,
})

async function ensureSchema() {
  await pool.query(`CREATE TABLE IF NOT EXISTS items (id SERIAL PRIMARY KEY, message TEXT NOT NULL)`)
  const { rows } = await pool.query('SELECT COUNT(*)::int AS n FROM items')
  if (rows[0].n === 0) {
    await pool.query(`INSERT INTO items (message) VALUES ('Hello from Postgres!')`)
  }
}

await ensureSchema()

const app = express()
app.use(cors())

app.get('/api/items', async (_req, res) => {
  const { rows } = await pool.query('SELECT id, message FROM items ORDER BY id')
  res.json(rows)
})

app.listen(PORT, '0.0.0.0', () => {
  console.log(`PERN API listening on http://localhost:${PORT}`)
})
