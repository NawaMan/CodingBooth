# Egress Allowlist + Extra Example

This example is a network-egress-controlled booth that locks down which domains the container may reach. With `egress = true`, the allowlist is read from `.booth/egress/allowlist.txt` (pypi.org) and merged with extra domains from `.booth/config.toml` (www.python.org), while everything else — like reddit.com or a direct-connect bypass — is refused. This is deny-by-default networking: outbound traffic is refused unless the destination is on your allowlist, which you keep in a reviewable, committed file rather than tribal knowledge. It's exactly the guardrail you want before handing an AI agent or an untrusted npm/pip dependency a shell — it can still reach PyPI to do real work, but it cannot quietly phone home, exfiltrate your source, or pull a payload from an arbitrary host. Lock egress down once, commit the policy, and every teammate's booth inherits the same boundary.

**Security note (2026-02-06):** `--egress` with `--dind` is **not supported**.  
DinD can bypass the egress firewall by running a privileged container in the shared network namespace. Use `--egress` **without** `--dind` until further research.

Enforcement uses:

- Envoy forward proxy policy (domain allowlist)
- iptables egress rules (force traffic through proxy)

## Quick run

```bash
cd examples/workspaces/egress-allowlist-extra-example
./booth
```

### Files to look at

- `.booth/config.toml` — shows `egress-allowlist` extra entries
- `.booth/egress/allowlist.txt` — base allowlist file

### Example behavior (inside container)

```bash
# allowed — from the file (.booth/egress/allowlist.txt)
curl -I -x http://127.0.0.1:15001 https://pypi.org
#   HTTP/1.1 200 OK            <- the proxy opened the tunnel
#   HTTP/2 200                 <- pypi.org answered

# allowed — from egress-allowlist in .booth/config.toml
curl -I -x http://127.0.0.1:15001 https://www.python.org
#   HTTP/1.1 200 OK
#   HTTP/2 200

# blocked by policy — on neither list
curl -I -x http://127.0.0.1:15001 https://reddit.com
#   HTTP/1.1 403 Forbidden
#   curl: (7) CONNECT tunnel failed, response 403

# direct bypass, skipping the proxy — dropped by the firewall
curl -I --noproxy '*' --max-time 8 https://google.com
#   curl: (28) Connection timed out after 8000 milliseconds
```

`--noproxy '*'` is what skips the proxy: the booth sets both `HTTPS_PROXY` and `https_proxy`, so
blanking only the uppercase one still goes through the proxy (and gets its 403, not the firewall).

Only a **403** from the proxy means "blocked by policy". A **503** means the proxy allowed the
domain but could not reach it — usually DNS: check `nslookup <domain>` on the host.

### Enable a domain

Add `reddit.com` to either list, then restart the booth (exit it and run `./booth` again) — the
policy is read when the booth starts:

- the file: append a line `reddit.com` to `.booth/egress/allowlist.txt`, or
- the config: `egress-allowlist = ["www.python.org", "reddit.com"]` in `.booth/config.toml`
  (regenerate it with `booth config --set egress-allowlist=www.python.org,reddit.com` rather than
  editing by hand).

The `reddit.com` check above then gets `HTTP/1.1 200 OK` from the proxy instead of `403 Forbidden`
(reddit.com itself answers with a `301` redirect to www.reddit.com).

### Run it

```bash
just --list
just verify              # .cb-tests/test-on-container.sh — every check below at once
just allowed             # pypi.org (file) and www.python.org (config), through the proxy
just blocked             # reddit.com — refused by the proxy with a 403
just bypass              # a direct connection, skipping the proxy — refused by the firewall
```

## Run tests

```bash
./run-automatic-on-host-test.sh
```
