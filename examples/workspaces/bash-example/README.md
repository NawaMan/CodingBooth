# Bash Example

A small `#!/bin/bash` script run with GNU Bash 3.2.57, installed beside the image's own bash as `bash-3.2`. The login shell stays the distro bash.

This is useful for testing scripts the way macOS does. macOS still ships Bash 3.2 as `/bin/bash`. On that shell, `"${items[@]}"` with an empty array is an error when `set -u` is on. `${items[@]+"${items[@]}"}` expands to nothing, which is what `scripts/count-args.sh` uses. The same script runs on the newer bash too.

## Which bash runs

`use-bash 3.2 <cmd>` runs `<cmd>` with 3.2 as every bash it starts, the script left unedited:

| Under `use-bash 3.2 ./script.sh` | Bash |
|---|---|
| `script.sh` itself, sourced files, functions, `$(…)` | 3.2 |
| a child or grandchild with `#!/bin/bash` | 3.2 |
| `#!/usr/bin/env bash`, `bash other.sh`, `bash -c` | 3.2 |
| `#!/bin/sh`, `sh -c` | dash |

Outside `use-bash`, every one of those is the distro bash, booth's own scripts included. `bash-3.2 ./script.sh` runs only that script on 3.2; its children follow their shebang. `use-bash 3.2` with no command opens a shell where every bash is 3.2; `exit` leaves it. `use-bash --list` shows what is installed, and `use-bash distro <cmd>` gets the image's bash back inside such a shell.

How: `setup bash` moves the distro bash to `/usr/bin/bash.distro` (a `dpkg-divert`, so apt upgrades still land) and puts a small dispatcher at `/usr/bin/bash`. The dispatcher runs `$CB_BASH` when it is set and the distro bash otherwise. `use-bash` sets `CB_BASH`, and every child inherits it. Seen from inside: `ps` and `$BASH` show `/usr/bin/bash.distro`, and coder logs in with that binary.

**Stack:** Bash 3.2.57 (`bash-3.2`)

## Quick start

```bash
cd examples/workspaces/bash-example
../../../codingbooth

# inside the booth
bash-3.2 --version
use-bash 3.2 ./scripts/count-args.sh
use-bash 3.2 ./scripts/count-args.sh one two
use-bash 3.2          # a shell where every bash is 3.2
just count
```

## What's included

| Component | Details |
|-----------|---------|
| Shell | Bash 3.2.57 at `/opt/bash/bash-3.2.57`, command `bash-3.2` |
| Switch | `use-bash 3.2 <cmd>`: every bash under `<cmd>` is 3.2 |
| Login shell | the distro bash (unchanged) |
| Sample | `scripts/count-args.sh` |

Pin another release with `GNU_BASH_VERSION` in `.booth/Boothfile` (`bash:5.2.37`), or `@bash` for the recipe in `.booth/recipes/bash.recipe`. The arg is not named `BASH_VERSION`: that name is bash's own version string, and the image build shell would substitute the distro bash.

Select `bash+default` when this build should be the login shell (`USER_SHELL=/opt/bash/bash-3.2.57/bin/bash` for the default pin). That login shell also sets `CB_BASH`, so the whole session acts as if started under `use-bash 3.2`, booth helpers included. This example leaves the login shell at the distro bash. `booth -- <cmd>` runs with the distro bash either way; `booth -- use-bash 3.2 <cmd>` runs it on 3.2.
