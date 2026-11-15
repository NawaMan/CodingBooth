// Notes API — the "backend" of the share-example app.
// Plain Node (no npm install). Data lives in memory: restart = empty board.
//
//   GET    /api/health        -> { ok: true, ... }
//   GET    /api/notes         -> [ { id, text, author, created } ]
//   POST   /api/notes         <- { text, author? }
//   DELETE /api/notes/:id
//
// Run: node --watch api/server.js   (restarts when you edit this file)

const http = require('node:http');

const PORT = Number(process.env.NOTES_API_PORT || 3001);
const notes = [
  { id: 1, text: 'Edit api/server.js or web/public/ and see it change', author: 'share-example', created: new Date().toISOString() },
];
let nextId = 2;

function send(res, status, body) {
  res.writeHead(status, {
    'Content-Type': 'application/json',
    // Open CORS: when the API is shared on its own URL, a teammate's own front end can call it.
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  });
  res.end(body === undefined ? '' : JSON.stringify(body));
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (c) => { data += c; if (data.length > 1e5) req.destroy(); });
    req.on('end', () => { try { resolve(data ? JSON.parse(data) : {}); } catch (e) { reject(e); } });
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  console.log(`${new Date().toISOString()} ${req.method} ${url.pathname}`);

  if (req.method === 'OPTIONS') return send(res, 204);

  if (url.pathname === '/api/health' && req.method === 'GET') {
    return send(res, 200, { ok: true, service: 'notes-api', notes: notes.length });
  }

  if (url.pathname === '/api/notes' && req.method === 'GET') {
    return send(res, 200, notes);
  }

  if (url.pathname === '/api/notes' && req.method === 'POST') {
    let body;
    try { body = await readJson(req); } catch { return send(res, 400, { error: 'body must be JSON' }); }
    const text = String(body.text || '').trim().slice(0, 500);
    if (!text) return send(res, 400, { error: 'text is required' });
    const note = { id: nextId++, text, author: String(body.author || 'anonymous').slice(0, 40), created: new Date().toISOString() };
    notes.push(note);
    return send(res, 201, note);
  }

  const m = url.pathname.match(/^\/api\/notes\/(\d+)$/);
  if (m && req.method === 'DELETE') {
    const i = notes.findIndex((n) => n.id === Number(m[1]));
    if (i < 0) return send(res, 404, { error: 'no such note' });
    notes.splice(i, 1);
    return send(res, 204);
  }

  send(res, 404, { error: `no route for ${req.method} ${url.pathname}` });
});

server.listen(PORT, () => console.log(`notes API on http://localhost:${PORT}/api/notes`));
