# Egress (Egress Filtering)

CodingBooth's egress feature provides **egress filtering and network isolation** for development containers.
When enabled, outbound HTTP/HTTPS connections are blocked unless the destination domain is explicitly allowlisted.

This prevents compromised dependencies, malicious code, or accidental connections from reaching unauthorized external services — a defense-in-depth layer for development environments.

---

## Quick Start

```bash
# Enable egress with default allowlist
./booth --egress

# Enable egress with a custom allowlist file
./booth --egress --egress-allowlist-file .booth/egress/allowlist.txt

# Enable egress with a custom Envoy policy
./booth --egress --egress-policy-file .booth/egress/envoy.yaml
```

Or in `.booth/config.toml`:

```toml
egress = true
```

---

## How It Works

The egress uses a multi-layer defense approach:

```
┌───────────────────────────────────────────────────────────────┐
│                           Host                                │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │        Egress Network (isolated namespace)             │  │
│  │                                                         │  │
│  │  ┌───────────────────────┐  ┌────────────────────────┐  │  │
│  │  │  Egress Netns Owner  │  │  Envoy Proxy Sidecar   │  │  │
│  │  │  (docker:dind)        │  │  (envoyproxy/envoy)    │  │  │
│  │  │                       │  │                        │  │  │
│  │  │  - Owns the network   │  │  - Forward proxy       │  │  │
│  │  │    namespace          │  │  - RBAC domain filter  │  │  │
│  │  │  - iptables firewall  │  │  - Port 15001          │  │  │
│  │  └───────────▲───────────┘  └────────────▲───────────┘  │  │
│  │              │  Shared network namespace │              │  │
│  │  ┌───────────┴───────────────────────────┴───────────┐  │  │
│  │  │   Booth Container                                 │  │  │
│  │  │                                                   │  │  │
│  │  │  - User code                                      │  │  │
│  │  │  - HTTP_PROXY=http://127.0.0.1:15001              │  │  │
│  │  │  - iptables blocks direct outbound                │  │  │
│  │  │  - Only proxy can reach the internet              │  │  │
│  │  └───────────────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

**Three layers enforce egress control:**

1. **Envoy Forward Proxy** — An HTTP/HTTPS proxy that uses RBAC rules to allow or deny requests based on destination domain. Runs on port 15001.

2. **Network Namespace Owner** — A dedicated sidecar that owns the isolated network namespace. When `--dind` is also enabled, the DinD sidecar fills this role instead.

3. **iptables Firewall** — Rules applied inside the shared network namespace that force all outbound traffic through the proxy. Direct connections to the internet are dropped.

### Firewall Rules

The iptables rules enforce that only the Envoy process (UID 101) can make direct outbound connections:

```
iptables -A OUTPUT -o lo -j ACCEPT                                    # loopback
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT                        # DNS
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT                        # DNS
iptables -A OUTPUT -p tcp -d 127.0.0.1 --dport 15001 -j ACCEPT        # proxy
iptables -A OUTPUT -m owner --uid-owner 101 -p tcp --dport 80 -j ACCEPT   # envoy → HTTP
iptables -A OUTPUT -m owner --uid-owner 101 -p tcp --dport 443 -j ACCEPT  # envoy → HTTPS
iptables -P OUTPUT DROP                                                # deny all else
```

### Proxy Environment Variables

When egress is enabled, these are set automatically inside the container:

```bash
http_proxy=http://127.0.0.1:15001
HTTP_PROXY=http://127.0.0.1:15001
https_proxy=http://127.0.0.1:15001
HTTPS_PROXY=http://127.0.0.1:15001
no_proxy=127.0.0.1,localhost
NO_PROXY=127.0.0.1,localhost
```

---

## Configuration

There are three ways to configure which domains are allowed. They are **mutually exclusive** (you cannot use both an allowlist file and a policy file).

### 1. Default Allowlist (No Configuration Needed)

If you enable `--egress` without specifying an allowlist or policy file, CodingBooth auto-creates `.booth/egress/allowlist.txt` with a comprehensive default allowlist covering common development services:

- **Source control** — GitHub, GitLab, Bitbucket, Codeberg
- **Container registries** — Docker Hub, GCR, ECR, GHCR, Quay
- **Package managers** — PyPI, npm, crates.io, Maven Central, RubyGems, Go modules, and more
- **CDNs** — jsDelivr, unpkg, Google Fonts, cdnjs
- **IDE extensions** — VS Code Marketplace, JetBrains Plugins
- **Cloud providers** — AWS, Azure, GCP
- **AI services** — Anthropic, OpenAI, GitHub Copilot
- **Linux repos** — Ubuntu, Debian, Fedora

### 2. Allowlist File

Create a simple domain-per-line allowlist:

```toml
# .booth/config.toml
egress = true
egress-allowlist-file = ".booth/egress/allowlist.txt"
```

**Allowlist format:**

```
# .booth/egress/allowlist.txt
# Lines starting with # are comments

github.com          # includes *.github.com
pypi.org
registry.npmjs.org
my-private-registry.company.com
```

Each domain automatically allows all subdomains and any port. For example, `pypi.org` matches `pypi.org`, `files.pypi.org`, and `pypi.org:8443`.

**Extra domains** can be merged on top of an allowlist file using `egress-allowlist`:

```toml
# .booth/config.toml
egress = true
egress-allowlist-file = ".booth/egress/allowlist.txt"
egress-allowlist = [
    "extra.example.com",
    "another.domain.org"
]
```

### 3. Custom Envoy Policy File

For full control over filtering rules, provide a custom Envoy YAML configuration:

```toml
# .booth/config.toml
egress = true
egress-policy-file = ".booth/egress/envoy.yaml"
```

This gives you access to the full Envoy RBAC system — regex matching, header inspection, path-based rules, and more. See the `egress-envoy-example` workspace for a working example.

---

## CLI Flags

| Flag                          | Description                                              | Default     |
|-------------------------------|----------------------------------------------------------|-------------|
| `--egress`                 | Enable egress                                    | `false`     |
| `--egress-mode <mode>`       | Proxy mode (`envoy`, `none`)                             | `envoy`     |
| `--egress-enforcement <type>`| Firewall enforcement (`iptables`, `nftables`, `none`)    | `iptables`  |
| `--egress-allowlist-file <path>` | Path to domain allowlist file                        | auto-detect |
| `--egress-policy-file <path>`| Path to custom Envoy YAML policy                         | —           |

All flags also support `config.toml` entries and environment variables (e.g., `CB_EGRESS_ALLOWLIST`).

---

## Limitations

- **`--egress` with `--dind` is not supported.** DinD runs privileged containers that can bypass the firewall rules in the shared network namespace.
- **The default allowlist is inevitably incomplete.** New dependencies or services may require allowlist updates. Review and customize for your project.
- **Only HTTP/HTTPS egress is filtered.** Other protocols (SSH, custom TCP) are blocked by the iptables rules but not proxied.

---

## Sidecar Architecture

The egress creates up to two sidecar containers:

| Sidecar       | Image                           | Purpose                           |
|---------------|----------------------------------|-----------------------------------|
| Netns owner   | `docker:dind`                    | Dedicated network namespace owner |
| Envoy proxy   | `envoyproxy/envoy:v1.31-latest`  | HTTP/HTTPS forward proxy          |

When `--dind` is also enabled, the DinD sidecar doubles as the network namespace owner — no separate netns sidecar is created.

### Naming Convention

Container and network names follow the pattern `{booth-name}-{port}-{suffix}`:

| Resource        | Name Pattern                    | Example                           |
|-----------------|---------------------------------|-----------------------------------|
| Netns owner     | `{name}-{port}-egress-netns`   | `myproject-10000-egress-netns`   |
| Envoy proxy     | `{name}-{port}-egress-proxy`   | `myproject-10000-egress-proxy`   |
| Egress network | `{name}-{port}-egress-net`     | `myproject-10000-egress-net`     |

### Labels

Every sidecar is labeled for lifecycle management:

| Label        | Value     | Purpose                                           |
|--------------|-----------|---------------------------------------------------|
| `cb.managed` | `true`    | Marks as a CodingBooth-managed container          |
| `cb.role`    | `sidecar` | Distinguishes sidecars from main booth containers |
| `cb.parent`  | `{name}`  | Links the sidecar to its parent booth container   |

### Cleanup

Egress sidecars are cleaned up through multiple mechanisms:

- **Normal exit** — `cleanupEgressResources()` stops the proxy, netns owner, and removes the egress network.
- **Pre-run cleanup** — Before starting a new booth, leftover sidecars from previous abnormal exits are removed using label-based queries.
- **Lifecycle commands** — `codingbooth stop`, `remove`, and `prune` all handle sidecar cleanup.
- **Daemon mode** — Sidecars are not auto-cleaned; use `codingbooth stop` to clean up.

### Startup Flow

```
BoothRunner.Run()
  -> SetupEgress(ctx)
       -> startEgressNetnsOwner()       // {name}-{port}-egress-netns (skipped if DinD)
       -> startEgressProxy()            // {name}-{port}-egress-proxy
       -> waitForEgressProxyReady()     // health check on port 15001
       -> applyEgressFirewall()         // iptables rules
  -> PrepareCommonArgs(ctx)              // sets proxy env vars
  -> booth.Run()
```

---

## Examples

CodingBooth includes several example workspaces demonstrating the egress feature:

| Example                         | What it demonstrates                                       |
|---------------------------------|------------------------------------------------------------|
| `firewall-example`              | Egress enforcement with Envoy + iptables                   |
| `egress-allowlist-extra-example`| Allowlist file with extra domains merged via config        |
| `egress-envoy-example`         | Custom `envoy.yaml` policy (allows only `pypi.org`)       |

Try an example:

```bash
./booth example try egress-envoy-example my-egress-test
cd my-egress-test
./booth
```

---

## Source Files

| File                                    | Responsibility                                              |
|-----------------------------------------|-------------------------------------------------------------|
| `cli/src/pkg/booth/egress_setup.go`    | Sidecar creation, Envoy config generation, firewall, cleanup|
| `cli/src/pkg/booth/booth_runner.go`     | Orchestration — calls `SetupEgress()`                      |
| `cli/src/pkg/booth/booth.go`            | Normal exit cleanup                                         |
| `cli/src/pkg/defaults/example-allowlist.txt` | Default allowlist template                             |
| `cli/src/pkg/lifecycle/lifecycle.go`    | Lifecycle commands with sidecar cleanup                     |
