# URL Whitelist Example

This example demonstrates the **network whitelist** feature, which restricts container internet access to only approved domains.

## What This Example Shows

- How to enable network whitelist in a container
- Default whitelisted domains (package registries)
- Adding custom domains via `.booth/home/.network-whitelist`
- Testing that blocked domains are inaccessible

## Files

| File                              | Purpose                                      |
|:----------------------------------|:---------------------------------------------|
| `.booth/Dockerfile`               | Installs `network-whitelist` setup           |
| `.booth/config.toml`              | Basic booth configuration                    |
| `.booth/home/.network-whitelist`  | Team-shared custom whitelist (adds httpbin)  |
| `test-on-container.sh`            | Tests run inside the container               |

## Usage

### Start the Container

```bash
../../booth
```

### Enable Network Whitelist

Once inside the container:

```bash
network-whitelist-enable
```

### Test Access

```bash
# Should work (whitelisted by default)
curl -I https://pypi.org

# Should work (added in .booth/home/.network-whitelist)
curl -I https://httpbin.org

# Should FAIL (not whitelisted)
curl -I https://example.com
```

### View Status

```bash
network-whitelist-status
network-whitelist-list
```

### Add More Domains

```bash
network-whitelist-add myapi.example.com
network-whitelist-reload
```

## Running Tests

From the host:

```bash
./run-automatic-on-host-test.sh
```

This will:
1. Start the container
2. Enable network whitelist
3. Test that whitelisted domains are accessible
4. Test that non-whitelisted domains are blocked
5. Clean up

## How It Works

1. The `network-whitelist--setup.sh` installs `tinyproxy` as an HTTP proxy
2. When enabled, `HTTP_PROXY` and `HTTPS_PROXY` environment variables are set
3. All HTTP/HTTPS traffic goes through the proxy
4. The proxy only allows connections to whitelisted domains
5. Package managers (npm, pip, maven, etc.) automatically use the proxy
