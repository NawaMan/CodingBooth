# Server Example

This example is a minimal HTTP server that demonstrates exposing a port from a CodingBooth to the host. A Python 3 `http.server` runs inside the booth on port 8080, serving the static page in `www/`. Because the booth auto-forwards that port to the host, opening `http://localhost:8080` in your own browser just works the moment the server starts — no `-p` flags, no `docker run` incantation, no reverse proxy to stand up. The process inside the booth binds a normal port and the booth quietly bridges it to your desktop, so the loop from "edit code" to "refresh the tab" stays as tight as running it natively.

**Stack:** Python 3.12 (`http.server`)

## Quick start

```bash
# 1. Launch the booth
cd examples/server-example
../../codingbooth

# 2. Inside the booth — start the server
./start-server.sh          # serves www/ on port 8080

# 3. Verify from inside the booth
curl http://localhost:8080

# 4. Open in your host browser
#    http://localhost:8080   — you should see the page from www/

# 5. Stop the server
./stop-server.sh
```

## How it works

`start-server.sh` runs `python -m http.server 8080` serving static files from the `www/` directory.
The port is forwarded to your host so you can access it from your browser.

## Scripts

| Script             | Description                         |
|--------------------|-------------------------------------|
| `start-server.sh` | Starts the HTTP server on port 8080 |
| `stop-server.sh`  | Stops the server                    |
