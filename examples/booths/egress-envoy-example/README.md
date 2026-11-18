# Egress Envoy Policy Example

This example is a network-egress-controlled booth whose allowlist comes from a hand-authored Envoy policy. With `egress = true` and `egress-policy-file = ".booth/egress/envoy.yaml"`, the custom Envoy RBAC config allows pypi.org while blocking every other domain (reddit.com, say) and any direct-connect bypass. Because a hand-authored Envoy policy is the single source of truth (backed by iptables rules that force traffic through the proxy), you control exactly which hosts the container may reach by editing one reviewable, committable file. When the built-in allowlist isn't expressive enough, you drop down to raw Envoy RBAC and shape egress precisely — then the whole team's booths enforce that identical policy. It's deny-by-default networking you can code-review like any other config, which is exactly what you want before turning an AI agent or untrusted dependency loose with a shell.

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
# allowed — by the allow_pypi rule in envoy.yaml
curl -I -x http://127.0.0.1:15001 https://pypi.org
#   HTTP/1.1 200 OK            <- the proxy opened the tunnel
#   HTTP/2 200                 <- pypi.org answered

# blocked by policy — no rule matches it
curl -I -x http://127.0.0.1:15001 https://reddit.com
#   HTTP/1.1 403 Forbidden
#   curl: (7) CONNECT tunnel failed, response 403

# direct bypass, skipping the proxy — dropped by the firewall
curl -I --noproxy '*' --max-time 8 https://google.com
#   curl: (28) Connection timed out after 8000 milliseconds
```

`--noproxy '*'` is what skips the proxy: the booth sets both `HTTPS_PROXY` and `https_proxy`, so
blanking only the uppercase one still goes through the proxy (and gets its 403, not the firewall).

Only a **403** from the proxy means "blocked by policy".

### Allow another domain

Each allowed domain is one RBAC policy in `.booth/egress/envoy.yaml`. To allow www.python.org, add
a policy next to `allow_pypi`:

```yaml
                  allow_python:
                    permissions:
                    - header:
                        name: ":authority"
                        string_match:
                          safe_regex:
                            google_re2: {}
                            regex: "^www\\.python\\.org(:[0-9]+)?$"
                    principals:
                    - any: true
```

Then restart the booth (exit it and run `./booth` again) — the policy is read when the booth
starts. `curl -I -x http://127.0.0.1:15001 https://www.python.org` now gets `HTTP/1.1 200 OK`
instead of `403 Forbidden`.

### Run it

```bash
just --list
just verify              # .cb-tests/test-on-container.sh — every check below at once
just allowed             # pypi.org, which envoy.yaml allows, through the proxy
just blocked             # reddit.com — refused by the proxy with a 403
just bypass              # a direct connection, skipping the proxy — refused by the firewall
just policy              # the RBAC rules in .booth/egress/envoy.yaml
```

## Run tests

```bash
./run-automatic-on-host-test.sh
```
