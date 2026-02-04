# Firewall Egress Sandbox Example

This example demonstrates the new `--sandbox` egress flow in CodingBooth.

It validates two scenarios:

1. `--sandbox` (dedicated sandbox network namespace sidecar)
2. `--sandbox --dind` (reuses DinD sidecar network namespace)

The policy is read from `.booth/egress/allowlist.txt` and enforced by:

- Envoy forward proxy policy (domain allowlist)
- iptables egress rules (force traffic through proxy)

## Quick run

```bash
cd examples/workspaces/firewall-example
../../../codingbooth --sandbox --variant base
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
