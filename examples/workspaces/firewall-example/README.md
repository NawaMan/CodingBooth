# Firewall Egress Sandbox Example

This example demonstrates the new `--sandboxed` egress flow in CodingBooth.

It validates the primary scenario:

1. `--sandboxed` (dedicated sandbox network namespace sidecar)

**Security note (2026-02-06):** `--sandboxed` with `--dind` is **not supported**.  
DinD can bypass the egress firewall by running a privileged container in the shared network namespace. Use `--sandboxed` **without** `--dind` until further research.

The policy is read from `.booth/egress/allowlist.txt` and enforced by:

- Envoy forward proxy policy (domain allowlist)
- iptables egress rules (force traffic through proxy)

## Quick run

```bash
cd examples/workspaces/firewall-example
../../../codingbooth --sandboxed --variant base
```

Inside the container:

```bash
# allowed
curl -I -x http://127.0.0.1:15001 https://pypi.org

# blocked by policy
curl -I -x http://127.0.0.1:15001 https://example.com

# direct bypass blocked by firewall
HTTPS_PROXY= HTTP_PROXY= curl -I --max-time 8 https://google.com
```

## Run tests

```bash
./run-automatic-on-host-test.sh
```
