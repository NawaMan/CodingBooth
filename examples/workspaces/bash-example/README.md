# Bash Example

A small script run with GNU Bash 3.2.57, installed beside the image's `/bin/bash` as `bash-3.2`. The login shell stays the distro bash.

This is useful for testing scripts the way macOS does. macOS still ships Bash 3.2 as `/bin/bash`. On that shell, `"${items[@]}"` with an empty array is an error when `set -u` is on. `${items[@]+"${items[@]}"}` expands to nothing, which is what `scripts/count-args.sh` uses. The same script runs on the newer `/bin/bash` too.

**Stack:** Bash 3.2.57 (`bash-3.2`)

## Quick start

```bash
cd examples/workspaces/bash-example
../../../codingbooth

# inside the booth
bash-3.2 --version
./scripts/count-args.sh
./scripts/count-args.sh one two
just count
```

## What's included

| Component | Details |
|-----------|---------|
| Shell | Bash 3.2.57 at `/opt/bash/bash-3.2.57`, command `bash-3.2` |
| Login shell | `/bin/bash` (unchanged) |
| Sample | `scripts/count-args.sh` |

Pin another release with `GNU_BASH_VERSION` in `.booth/Boothfile` (`bash:5.2.37`), or `@bash` for the recipe in `.booth/recipes/bash.recipe`. The arg is not named `BASH_VERSION`: that name is bash's own version string, and the image build shell would substitute the distro bash.

Select `bash+default` when this build should be the login shell (`USER_SHELL=/opt/bash/bash-3.2.57/bin/bash` for the default pin). This example leaves the login shell at `/bin/bash`. `booth -- <cmd>` runs with `/bin/bash` either way.
