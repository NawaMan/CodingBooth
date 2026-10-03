'use strict';

const http = require('http');
const port = process.env.SERVER_PORT || 3001;

const server = http.createServer((request, response) => {
  const url = request.url.split('?')[0];
  if (url === '/api/ping' || url === '/') {
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ online: true, app: 'AnythingLLM' }));
    return;
  }
  response.writeHead(404);
  response.end();
});

server.listen(port, '0.0.0.0', () => {
  process.stdout.write(`AnythingLLM fixture listening on ${port}\n`);
});
