# Template Authoring Guidelines

## Segment Ordering

When a template's `[segments]` section defines Boothfile content, the segment key controls
the order in the final generated Boothfile. All segments from all selected templates are
merged **globally** and sorted by order number, with alphabetical tiebreak by template name.

| Segment Key       | Order | Use for                                                  |
|--------------------|-------|----------------------------------------------------------|
| `Boothfile`        | 50    | Base/independent setups (java, python, go, nodejs, etc.) |
| `"Boothfile--60"`  | 60    | Setups that depend on a base (kotlin, scala, clojure need java; elixir needs erlang; IDEs need a desktop) |
| `"Boothfile--90"`  | 90    | Post-setup steps (pip/uv/conda install from requirements.txt, etc.) |

**Rule of thumb:** if your setup script assumes another setup has already run
(e.g., `JAVA_HOME` is set, or `cb-has-desktop.sh` passes), use a higher order number.

### Example

```toml
# Base language — uses default order (50)
[segments]
Boothfile = """
setup java ${JDK_VERSION} ${JDK_VENDOR}
"""

# Depends on Java — order 60, runs after all order-50 segments
[segments]
"Boothfile--60" = """
setup clojure
"""

# Post-setup — order 90, runs last
[segments]
"Boothfile--90" = """
run --mount=type=bind,target=/tmp/ctx \
    if [ -f /tmp/ctx/.booth/requirements.txt ]; then \
        pip install -r /tmp/ctx/.booth/requirements.txt; \
    fi
"""
```

### Tiebreaking

When two segments share the same order number, they are sorted alphabetically
by their source template name (e.g., "go" before "python" at order 50).

## Setup Script Arguments

Some setup scripts use a `while [[ $# -gt 0 ]]` argument parser that does **not**
accept bare positional version arguments. Always check the script's usage and prefer
the explicit flag form:

```toml
# Good — uses the flag the script expects
setup kotlin --version ${KOTLIN_VERSION}
setup scala --scala-version ${SCALA_VERSION}
setup lua --lua-version ${LUA_VERSION}
setup php --version ${PHP_VERSION}
setup kind --kind-version ${KIND_VERSION}

# Bad — may fail with "Unknown arg" if the script doesn't accept positional args
setup kotlin ${KOTLIN_VERSION}
```

Scripts that **do** accept a bare positional version (simple `$1` capture without a while loop):
`python`, `nodejs`, `bun`, `deno`, `ruby`, `neovim`, `jdk`.
