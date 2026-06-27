# Egress Envoy Policy Example

This example demonstrates `--egress` with a custom Envoy policy file.

**Security note (2026-02-06):** `--egress` with `--dind` is **not supported**.  
DinD can bypass the egress firewall by running a privileged container in the shared network namespace. Use `--egress` **without** `--dind` until further research.

The policy is read from `.booth/egress/envoy.yaml` and enforced by:

- Envoy forward proxy policy (domain allowlist)
- iptables egress rules (force traffic through proxy)

## Quick run

```bash
cd examples/workspaces/egress-envoy-example
./booth
```

### Files to look at

- `.booth/config.toml` — uses `egress-policy-file`
- `.booth/egress/envoy.yaml` — custom Envoy RBAC policy

### Example behavior (inside container)

```bash
# allowed (by custom envoy.yaml)
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
