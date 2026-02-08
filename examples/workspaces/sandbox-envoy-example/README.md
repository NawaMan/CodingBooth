# Sandbox Envoy Policy Example

This example demonstrates `--sandboxed` with a custom Envoy policy file.

**Security note (2026-02-06):** `--sandboxed` with `--dind` is **not supported**.  
DinD can bypass the egress firewall by running a privileged container in the shared network namespace. Use `--sandboxed` **without** `--dind` until further research.

The policy is read from `.booth/sandbox/envoy.yaml` and enforced by:

- Envoy forward proxy policy (domain allowlist)
- iptables egress rules (force traffic through proxy)

## Quick run

```bash
cd examples/workspaces/sandbox-envoy-example
./booth
```

### Files to look at

- `.booth/config.toml` — uses `sandbox-policy-file`
- `.booth/sandbox/envoy.yaml` — custom Envoy RBAC policy

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
