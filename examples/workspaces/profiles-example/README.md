# Profiles Example

One booth definition with two named profiles, `default` and `prod`, layered on top of the base `config.toml`. A profile is an overlay: it sets only the keys it names, and you pick it at start time with `--profile` (or `BOOTH_PROFILES`). Switching profiles never rebuilds the image.

`default` is a fallback, not an always-on layer. It applies when you select nothing, and it steps aside as soon as you select any other profile, unless you name it too (`--profile default,prod`).

See [docs/BOOTH_PROFILES.md](../../../docs/BOOTH_PROFILES.md) for the full rules.

## The files

| File | Sets | Committed |
|---|---|---|
| `.booth/config.toml` | `port = "50911"`, `--env FROM_BASE=yes` | yes (`booth config` output) |
| `.booth/default--config.toml` | `port = "50912"`, `--env FROM_DEFAULT=yes` | yes (hand-written) |
| `.booth/prod--config.toml` | `port = "50913"`, `--env FROM_PROD=yes` | yes (hand-written) |
| `.booth/.env` | `LEVEL=base` | no |
| `.booth/.default--env` | `LEVEL=default` | no |
| `.booth/.prod--env` | `LEVEL=prod` | no |

The env files are gitignored (`.env` and `.*--env` in `.booth/.gitignore`). Booth refuses to start with an env file that git tracks, since that is where secrets go. `just env-files` writes the samples above. Without them, everything works except `LEVEL`, which stays empty.

Each setting covers one merge rule:

- **`port`** is a scalar: the layer applied last wins. It shows up in the booth as `BOOTH_HOST_PORT`.
- **`run-args`** is a list: every layer's entries add up. That is why each layer sets its own variable rather than a shared one. Two layers setting the same `--env` name is an error, not an override.
- **Env files** are values: the profile applied last wins, on top of `.env`.

## Quick start

```bash
just env-files   # optional: the gitignored env files, for LEVEL
just none        # booth                         -> base + default
just prod        # booth --profile prod          -> base + prod
just both        # booth --profile default,prod  -> base + default + prod
just reversed    # booth --profile prod,default  -> the same, default last
just test        # all of the above, checked
```

Each recipe starts a one-shot booth and runs `scripts/show-profile.sh`, which prints the settings.

The recipes call `./booth`. In a CodingBooth checkout that wrapper is not committed: run `./examples/update-booth.sh` once from the repository root, or use `BOOTH=../../../codingbooth just none`.

## What you get

| Selection | `PORT` | `FROM_BASE` | `FROM_DEFAULT` | `FROM_PROD` | `LEVEL` |
|---|---|---|---|---|---|
| none | 50912 | yes | yes | — | default |
| `--profile prod` | 50913 | yes | — | yes | prod |
| `--profile default,prod` | 50913 | yes | yes | yes | prod |
| `--profile prod,default` | 50912 | yes | yes | yes | default |
| `BOOTH_PROFILES=prod` | 50913 | yes | — | yes | prod |

Things to notice:

- `FROM_BASE` is always there. The base is not a profile and cannot be deselected.
- With `--profile prod`, `FROM_DEFAULT` is gone and the port is prod's: selecting a profile drops `default`.
- With both selected, the lists combine (both `FROM_DEFAULT` and `FROM_PROD`), while the scalar and the env file come from whichever profile is listed **last**.
- A command-line `--port` beats every profile. The test passes none for that reason.

## Testing

`.cb-tests/test001-profiles--on-host.sh` runs every row of the table and checks each value. It runs on the host, because `--profile` is read there. It writes the sample env files if they are missing and removes only the ones it wrote.

```bash
./run-automatic-on-host-test.sh
# or, with the rest of the examples:
../run-example-tests.sh --example profiles-example
```
