# Network Whitelist Feature

This document describes the network whitelist feature for CodingBooth, which restricts container internet access to only approved domains.

## Overview

The network whitelist feature uses a lightweight HTTP proxy (tinyproxy) to filter outbound HTTP/HTTPS traffic. When installed, only connections to whitelisted domains are allowed - all other traffic is blocked with a `403 Filtered` response.

**Use cases:**
- Security-conscious development environments
- Compliance requirements that limit network access
- Ensuring containers only access approved package registries
- Preventing accidental data exfiltration

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│ Container                                                    │
│                                                              │
│  ┌──────────┐     ┌───────────────┐     ┌────────────────┐  │
│  │ App/CLI  │────▶│  tinyproxy    │────▶│   Internet     │  │
│  │ (curl,   │     │  (port 18888) │     │                │  │
│  │  npm,    │     │               │     │  Whitelisted   │  │
│  │  pip)    │     │  Checks       │     │  domains only  │  │
│  └──────────┘     │  whitelist    │     └────────────────┘  │
│       │           └───────────────┘                         │
│       │                  │                                  │
│       ▼                  ▼                                  │
│  HTTP_PROXY        ┌───────────┐                            │
│  HTTPS_PROXY       │ Whitelist │                            │
│  env vars          │   file    │                            │
│                    └───────────┘                            │
└─────────────────────────────────────────────────────────────┘
```

1. The `network-whitelist--setup.sh` script installs tinyproxy and configures it
2. `HTTP_PROXY` and `HTTPS_PROXY` environment variables are set to `http://127.0.0.1:18888`
3. Most tools (curl, wget, npm, pip, maven, etc.) automatically use these proxy variables
4. Tinyproxy checks each request against the whitelist file
5. Whitelisted domains: connection proceeds normally
6. Non-whitelisted domains: returns `403 Filtered`

## Installation

Add the setup script to your `.booth/Dockerfile`:

```dockerfile
FROM nawaman/codingbooth:base-latest

# Install network whitelist
RUN /opt/codingbooth/setups/network-whitelist--setup.sh

# ... other setups
```

**Important:** The network whitelist is **always enabled** when this setup is installed. There is no way to disable it from inside the container (by design, for security).

## Experimental: Firewall Enforcement

> **⚠️ EXPERIMENTAL FEATURE - NOT A SECURITY BOUNDARY**
>
> This feature is experimental and **can be bypassed by a determined bad actor** with shell access inside the container. It provides defense-in-depth but should not be relied upon as a security boundary. See "Known Bypass Methods" below.

By default, the network whitelist relies on applications respecting the `HTTP_PROXY` environment variables. A malicious actor could bypass this by unsetting these variables.

For stronger enforcement, you can enable iptables-based firewall rules that block direct HTTP/HTTPS connections, forcing all traffic through the proxy.

### Enabling Firewall Enforcement

Add `CAP_NET_ADMIN` capability in your `.booth/config.toml`:

```toml
run-args = [
    "--cap-add=NET_ADMIN",
]
```

When the container starts with this capability, the setup will automatically:
1. Block direct outgoing connections to ports 80 and 443
2. Allow only localhost connections (where the proxy runs)
3. Allow DNS queries (port 53)

This means even if someone runs `unset HTTP_PROXY && curl google.com`, the connection will be blocked at the firewall level.

### Verifying Firewall Enforcement

Inside the container, check if iptables rules are active:

```bash
sudo iptables -L OUTPUT -n
```

You should see rules blocking ports 80 and 443.

### Known Bypass Methods (Why This Is Experimental)

A bad actor with shell access inside the container could bypass this feature by:

1. **Modifying iptables rules** - If they have sudo access, they can flush or modify the firewall rules
2. **Killing tinyproxy** - Stop the proxy process and modify the whitelist
3. **Editing whitelist files** - Add their desired domains to `~/.network-whitelist`
4. **Using other ports** - The firewall only blocks ports 80 and 443; traffic on other ports (8080, 8443, etc.) is not affected
5. **Using non-HTTP protocols** - SSH tunneling, raw TCP connections, etc. are not filtered
6. **DNS exfiltration** - DNS queries are allowed for domain resolution

### What This Feature Is Good For

Despite the limitations, firewall enforcement is useful for:

- **Accidental bypass prevention** - Stops scripts that don't respect proxy environment variables
- **Defense in depth** - Adds another layer that must be bypassed
- **Compliance guardrails** - Demonstrates network controls are in place
- **Legitimate user guidance** - Makes it clear that network restrictions are intentional

### Security Considerations

With firewall enforcement enabled:
- Direct HTTP/HTTPS connections are blocked at the kernel level
- The proxy environment variables cannot be accidentally bypassed
- DNS queries are still allowed (for domain resolution)
- Other protocols (SSH, raw TCP on other ports) are not affected
- **A determined bad actor with sudo access CAN still bypass**

Without firewall enforcement (no `CAP_NET_ADMIN`):
- Security relies on applications respecting `HTTP_PROXY`
- A determined user can bypass by unsetting environment variables
- Still effective as a "guardrail" for legitimate use

### Future Improvements (Under Consideration)

For truly enforced network restrictions, future versions may explore:

1. **Docker network isolation** - Using `--network=none` with a sidecar proxy container
2. **Removing sudo access** - Preventing users from modifying iptables (may break other features)
3. **Network namespaces** - More granular network isolation at the container level
4. **External proxy/firewall** - Enforcing restrictions outside the container where users have no access

## Usage

### Check Status

```bash
network-whitelist-status
```

Output:
```
=== Network Whitelist Status ===

Status: ENABLED (always on when installed)

Proxy: Running (port 18888)

Whitelisted domains:
  Default: 45 domains
  User:    2 domains

Environment:
  HTTP_PROXY:  http://127.0.0.1:18888
  HTTPS_PROXY: http://127.0.0.1:18888
```

### View Whitelisted Domains

```bash
# Show all whitelists
network-whitelist-list

# Show only default whitelist
network-whitelist-list --default

# Show only user whitelist
network-whitelist-list --user

# Show combined active whitelist
network-whitelist-list --combined
```

### Add Custom Domains

**Option 1: Command line**
```bash
network-whitelist-add api.example.com
network-whitelist-add cdn.example.com storage.example.com
network-whitelist-reload
```

**Option 2: Edit file directly**
```bash
echo "api.example.com" >> ~/.network-whitelist
network-whitelist-reload
```

**Option 3: Team-shared whitelist**

Create `.booth/home/.network-whitelist` in your project:
```
# Company-specific domains
api.mycompany.com
cdn.mycompany.com
internal-registry.mycompany.com
```

This file is copied to `~/.network-whitelist` at container startup.

### Reload After Changes

After modifying the whitelist, apply changes:
```bash
network-whitelist-reload
```

## Available Commands

| Command                      | Description                              |
|:-----------------------------|:-----------------------------------------|
| `network-whitelist-status`   | Show current status and domain counts    |
| `network-whitelist-list`     | List whitelisted domains                 |
| `network-whitelist-add`      | Add domain(s) to user whitelist          |
| `network-whitelist-reload`   | Apply whitelist changes                  |

**Note:** There are no `enable` or `disable` commands. The whitelist is always enabled when installed and cannot be disabled from inside the container.

## Default Whitelisted Domains

The following domains are whitelisted by default to support common development workflows:

### Package Registries

| Category       | Domains                                                    |
|:---------------|:-----------------------------------------------------------|
| **npm/Node.js**| registry.npmjs.org, npmjs.org, npmjs.com, yarnpkg.com, nodejs.org, unpkg.com |
| **Python/PyPI**| pypi.org, files.pythonhosted.org, python.org               |
| **Maven/Java** | repo.maven.apache.org, repo1.maven.org, plugins.gradle.org, services.gradle.org |
| **Go**         | proxy.golang.org, sum.golang.org, golang.org, go.dev, pkg.go.dev |
| **Rust/Cargo** | crates.io, static.crates.io, index.crates.io, static.rust-lang.org |
| **Ruby/Gems**  | rubygems.org, api.rubygems.org                             |
| **PHP/Composer**| packagist.org, repo.packagist.org, getcomposer.org        |

### Container & Version Control

| Category       | Domains                                                    |
|:---------------|:-----------------------------------------------------------|
| **Docker**     | registry-1.docker.io, docker.io, auth.docker.io, hub.docker.com |
| **GitHub**     | github.com, api.github.com, raw.githubusercontent.com, codeload.github.com |
| **GitLab**     | gitlab.com, registry.gitlab.com                            |

### OS Packages

| Category       | Domains                                                    |
|:---------------|:-----------------------------------------------------------|
| **Ubuntu/Debian** | archive.ubuntu.com, security.ubuntu.com, ppa.launchpad.net, deb.debian.org |
| **Alpine**     | dl-cdn.alpinelinux.org                                     |

### IDEs & Tools

| Category       | Domains                                                    |
|:---------------|:-----------------------------------------------------------|
| **VS Code**    | marketplace.visualstudio.com, update.code.visualstudio.com, vscode.blob.core.windows.net |
| **JetBrains**  | download.jetbrains.com, plugins.jetbrains.com              |
| **Misc**       | astral.sh, brew.sh, deno.land, bun.sh                      |

## Whitelist File Format

The whitelist files use extended regular expressions (one per line):

```
# Comments start with #
# Blank lines are ignored

# Exact domain match
example.com

# Subdomain wildcard (regex syntax)
.*\.example\.com

# Multiple subdomains
api\.v[0-9]+\.example\.com
```

**Important:** Since tinyproxy uses extended regex:
- Use `\.` for literal dots (though plain `.` usually works for domain matching)
- Use `.*` for wildcards (not `*`)
- The pattern `*.example.com` is **invalid** - use `.*\.example\.com` instead

## File Locations

| File                                | Purpose                          |
|:------------------------------------|:---------------------------------|
| `/etc/tinyproxy/tinyproxy.conf`     | Proxy configuration              |
| `/etc/tinyproxy/default-whitelist.txt` | System default whitelist      |
| `/etc/tinyproxy/whitelist.txt`      | Combined active whitelist        |
| `~/.network-whitelist`              | User's custom whitelist          |
| `.booth/home/.network-whitelist`    | Team-shared whitelist (in repo)  |

## Limitations

1. **HTTP/HTTPS only** - The proxy only filters HTTP and HTTPS traffic. Other protocols (SSH, raw TCP, etc.) are not affected.

2. **Proxy-aware tools only** - Without firewall enforcement, tools must respect the `HTTP_PROXY`/`HTTPS_PROXY` environment variables. With firewall enforcement (`CAP_NET_ADMIN`), direct connections are blocked.

3. **No IP address filtering** - The whitelist works on domain names, not IP addresses. Direct IP connections bypass the proxy (unless firewall enforcement is enabled).

4. **DNS resolution** - DNS queries are not filtered. The domain is checked when the HTTP CONNECT request is made.

## Troubleshooting

### Proxy not starting

Check if tinyproxy is running:
```bash
pgrep -la tinyproxy
```

Check for configuration errors:
```bash
sudo tinyproxy -c /etc/tinyproxy/tinyproxy.conf -d
```

### Domain still blocked after adding

1. Make sure you ran `network-whitelist-reload`
2. Check the combined whitelist: `network-whitelist-list --combined`
3. Verify regex syntax (use `.*\.` not `*.`)

### Tools not using proxy

Some tools need explicit proxy configuration:
```bash
# Git
git config --global http.proxy $HTTP_PROXY
git config --global https.proxy $HTTPS_PROXY

# Docker (in daemon.json)
# "proxies": { "http-proxy": "...", "https-proxy": "..." }
```

### Check what's being blocked

Run curl with verbose output:
```bash
curl -v --proxy $HTTP_PROXY https://blocked-domain.com
```

Look for `403 Filtered` in the response.

### Firewall rules not working

Make sure the container has `CAP_NET_ADMIN`:
```bash
# In config.toml
run-args = ["--cap-add=NET_ADMIN"]
```

Check if iptables rules are present:
```bash
sudo iptables -L OUTPUT -n
```

## Example Project

See `examples/workspaces/urlwhitelist-example/` for a complete working example with tests.

```bash
cd examples/workspaces/urlwhitelist-example
../../../coding-booth -- bash

# Inside container:
network-whitelist-status
curl -I https://pypi.org      # Works (whitelisted)
curl -I https://example.com   # Blocked (not whitelisted)

# Test firewall enforcement (if CAP_NET_ADMIN enabled)
unset HTTP_PROXY HTTPS_PROXY
curl https://google.com       # Still blocked by iptables
```
