// Use node: prefix for built-in modules (works in Node.js 16+ and Deno)
import fs from 'node:fs';
import path from 'node:path';

// Dynamic import for express to support both Node.js and Deno
// @ts-ignore: Deno uses npm: specifier
const express = (await import(
  // @ts-ignore: Runtime detection
  typeof Deno !== 'undefined' ? 'npm:express' : 'express'
)).default;

const app = express();
const PORT = process.env.PORT ? Number(process.env.PORT) : 3000;

// Detect built client (Vite) in production
const distDir = path.resolve(process.cwd(), 'dist');
const indexHtmlPath = path.join(distDir, 'index.html');
const hasBuiltClient = fs.existsSync(indexHtmlPath);

// If built assets exist, serve them as static files
if (hasBuiltClient) {
  app.use(express.static(distDir));
} else {
  // Dev helper root route (when no built UI is present)
  const devInfoHtml = `<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Time App Server</title>
    <style>body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;padding:2rem;line-height:1.5} code{background:#f5f5f5;padding:.15rem .35rem;border-radius:4px}</style>
  </head>
  <body>
    <h1>Time App API</h1>
    <p>Server is running on port ${PORT}.</p>
    <ul>
      <li>API: <a href="/api/time">/api/time</a></li>
      <li>API (alias): <a href="/api/currenttime">/api/currenttime</a></li>
    </ul>
    <p>Client (Vite) runs separately on <code>http://localhost:5173</code> during development.</p>
  </body>
</html>`;

  app.get('/', (_req, res) => {
    res.type('html').send(devInfoHtml);
  });

  // Also serve /index.html in dev to avoid 404
  app.get('/index.html', (_req, res) => {
    res.type('html').send(devInfoHtml);
  });
}

app.get('/api/time', (_req, res) => {
  const now = new Date();
  res.json({
    iso: now.toISOString(),
    epochMs: now.getTime(),
    locale: now.toLocaleString(),
  });
});

// New endpoint to return current server time (same payload)
app.get('/api/currenttime', (_req, res) => {
  const now = new Date();
  res.json({
    iso: now.toISOString(),
    epochMs: now.getTime(),
    locale: now.toLocaleString(),
  });
});

// SPA fallback: after API routes, if built client exists, send index.html for any other route
if (hasBuiltClient) {
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api')) return next();
    res.sendFile(indexHtmlPath);
  });
}

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Server listening on http://localhost:${PORT}`);
});
