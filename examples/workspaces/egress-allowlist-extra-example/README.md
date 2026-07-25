# Egress Allowlist + Extra Example

This example is a network-egress-controlled booth that locks down which domains the container may reach. With `egress = true`, the allowlist is read from `.booth/egress/allowlist.txt` (pypi.org) and merged with extra domains from `.booth/config.toml` (example.com), while everything else — like reddit.com or a direct-connect bypass — is refused. This is deny-by-default networking: outbound traffic is refused unless the destination is on your allowlist, which you keep in a reviewable, committed file rather than tribal knowledge. It's exactly the guardrail you want before handing an AI agent or an untrusted npm/pip dependency a shell — it can still reach PyPI to do real work, but it cannot quietly phone home, exfiltrate your source, or pull a payload from an arbitrary host. Lock egress down once, commit the policy, and every teammate's booth inherits the same boundary.

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
