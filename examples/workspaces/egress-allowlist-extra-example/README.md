# Egress Allowlist + Extra Example

This example demonstrates `--egress` with:
- a file-based allowlist, and
- extra domains appended via `egress-allowlist`.

**Security note (2026-02-06):** `--egress` with `--dind` is **not supported**.  
DinD can bypass the egress firewall by running a privileged container in the shared network namespace. Use `--egress` **without** `--dind` until further research.

The policy is read from `.booth/egress/allowlist.txt` and merged with `egress-allowlist` in `.booth/config.toml`.
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
# allowed (from file)
curl -I -x http://127.0.0.1:15001 https://pypi.org

# allowed (from egress-allowlist extra)
curl -I -x http://127.0.0.1:15001 https://example.com

# blocked by policy
curl -I -x http://127.0.0.1:15001 https://reddit.com

# direct bypass blocked by firewall
HTTPS_PROXY= HTTP_PROXY= curl -I --max-time 8 https://google.com
```

## Run tests

```bash
./run-automatic-on-host-test.sh
```
