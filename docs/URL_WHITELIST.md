# Network Whitelist Feature

This document describes the network whitelist feature for CodingBooth, which restricts container internet access to only approved domains.

## Overview

The network whitelist feature uses a lightweight HTTP proxy (tinyproxy) to filter outbound HTTP/HTTPS traffic. When enabled, only connections to whitelisted domains are allowed - all other traffic is blocked with a `403 Filtered` response.

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
2. When enabled, `HTTP_PROXY` and `HTTPS_PROXY` environment variables are set to `http://127.0.0.1:18888`
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

## Usage

### Enable Network Whitelist

The whitelist is **disabled by default** for backwards compatibility. Enable it inside the container:

```bash
network-whitelist-enable
```

This will:
1. Create the enabled flag file (`~/.network-whitelist-enabled`)
2. Combine default and user whitelists
3. Start the tinyproxy proxy
4. Set environment variables in new shell sessions

**Important:** After enabling, start a new shell session or source the profile:
```bash
source /etc/profile.d/40-cb-network-whitelist--profile.sh
```

### Disable Network Whitelist

```bash
network-whitelist-disable
```

Then start a new shell session or manually unset the proxy variables:
```bash
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy
```

### Check Status

```bash
network-whitelist-status
```

Output:
```
=== Network Whitelist Status ===

Status: ENABLED

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
| `network-whitelist-enable`   | Enable network restrictions              |
| `network-whitelist-disable`  | Disable network restrictions             |
| `network-whitelist-status`   | Show current status and domain counts    |
| `network-whitelist-list`     | List whitelisted domains                 |
| `network-whitelist-add`      | Add domain(s) to user whitelist          |
| `network-whitelist-reload`   | Apply whitelist changes                  |

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
| `~/.network-whitelist-enabled`      | Flag file (presence = enabled)   |
| `.booth/home/.network-whitelist`    | Team-shared whitelist (in repo)  |

## Limitations

1. **HTTP/HTTPS only** - The proxy only filters HTTP and HTTPS traffic. Other protocols (SSH, raw TCP, etc.) are not affected.

2. **Proxy-aware tools only** - Tools must respect the `HTTP_PROXY`/`HTTPS_PROXY` environment variables. Most package managers do, but some tools may not.

3. **No IP address filtering** - The whitelist works on domain names, not IP addresses. Direct IP connections bypass the proxy.

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

## Example Project

See `examples/workspaces/urlwhitelist-example/` for a complete working example with tests.

```bash
cd examples/workspaces/urlwhitelist-example
../../booth --daemon
docker exec -it urlwhitelist-example bash -l

# Inside container:
network-whitelist-enable
network-whitelist-status
curl -I https://pypi.org      # Works (whitelisted)
curl -I https://example.com   # Blocked (not whitelisted)
```
