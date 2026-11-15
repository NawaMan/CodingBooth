// Front-end dev server for the share-example app.
// Serves web/public/ and forwards /api/* to the API server, the way a Vite or
// webpack dev server proxies to a backend. Because of that proxy, sharing this
// one port shares the whole app: the page and its API calls.
//
// Run: node --watch web/server.js   (files in web/public/ are read fresh on every request)

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const PORT = Number(process.env.WEB_PORT || 8080);
const API = `http://localhost:${Number(process.env.API_PORT || 3001)}`;
const ROOT = path.join(__dirname, 'public');
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml' };

function proxy(req, res) {
  const upstream = http.request(API + req.url, { method: req.method, headers: req.headers }, (up) => {
    res.writeHead(up.statusCode, up.headers);
    up.pipe(res);
  });
  upstream.on('error', () => {
    res.writeHead(502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: `API not reachable at ${API} — is it running? (just dev)` }));
  });
  req.pipe(upstream);
}

const server = http.createServer((req, res) => {
  if (req.url.startsWith('/api/')) return proxy(req, res);

  const urlPath = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  const file = path.join(ROOT, urlPath === '/' ? 'index.html' : urlPath);
  if (!file.startsWith(ROOT)) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404, { 'Content-Type': 'text/plain' }); return res.end('not found'); }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    res.end(data);
  });
});

server.listen(PORT, () => console.log(`front end on http://localhost:${PORT}  (API proxied to ${API})`));
