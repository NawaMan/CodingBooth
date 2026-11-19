// A tiny static server for served/, so the served test needs nothing beyond Node.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(fileURLToPath(import.meta.url));
const port = Number(process.env.PORT || 4321);

createServer(async (req, res) => {
  const name = req.url === '/' ? 'index.html' : req.url.slice(1);
  try {
    const body = await readFile(join(root, name.replace(/\.\./g, '')));
    res.writeHead(200, { 'Content-Type': name.endsWith('.html') ? 'text/html' : 'text/plain' });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
}).listen(port, '127.0.0.1', () => console.log(`serving ${root} on http://127.0.0.1:${port}`));
