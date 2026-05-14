# Booth Variable Expansion

> Bash-like variable expansion for values you write in `.booth/.env`,
> `.booth/config.toml`, and the `CB_*` environment variables. Booth resolves
> these *before* invoking docker, so values reach your container already
> substituted — including for `.booth/.env`, where docker's native
> `--env-file` would otherwise leave `$VAR` and `~` as literal text.

Back to [README](../README.md)

---

## Where expansion happens

| Source | Expanded? |
|---|---|
| `.booth/.env` | yes — booth writes an expanded copy to `.booth/.tmp/` and passes that to docker |
| `--env-file <path>` (explicit) | yes — same mechanism as `.booth/.env` |
| `config.toml` scalar fields (`image`, `port`, `env-file`, `name`, `timezone`, `dockerfile`, `boothfile`, `variant`, `project-name`, `host-uid`, `host-gid`, `startup`, sandbox-related paths) | yes |
| `config.toml` array fields (`run-args`, `build-args`, `common-args`, `cmds`) | yes — each element |
| `CB_*` environment variables (string or semicolon list) | yes |
| CLI `-e KEY=VAL` / `--env KEY=VAL` | **no** — the invoking shell has already done its expansion. Booth passes the value through to docker untouched |

---

## The rules

### Variable references

- `$NAME` — longest run of `[A-Za-z_][A-Za-z0-9_]*` after the `$`.
- `${NAME}` — explicit braces; allows operators (below).
- An unset variable expands to the empty string.
- A trailing `$` with no name is left as a literal `$`.

### Operators inside `${...}`

Only two are supported. Anything else is a parse error.

- `${NAME:-default}` — use `default` if `NAME` is unset **or empty**. `default` is itself expanded (so nested defaults work).
- `${NAME:?error message}` — if `NAME` is unset or empty, abort booth with a source-located error. The message is itself expanded. An empty message (`${NAME:?}`) falls back to `required variable NAME is not set`.

Both forms use the colon. Non-colon variants (`${NAME-x}`, `${NAME?x}`), assign-and-use (`${NAME:=x}`), alt-value (`${NAME:+x}`), substring, replacement, case, prefix/suffix strip, length, and indirection are **not** supported.

### Tilde

`~` expands to `$HOME` when it is the **first character of the value**, or the first character inside an opening `"..."` that itself starts the value. Anywhere else, `~` is literal.

```
~/data         → /home/you/data
"~/data"       → /home/you/data
'~/data'       → ~/data         (single quotes never expand)
prefix/~/x     → prefix/~/x     (not at start)
```

### Quoting

Quotes can appear mid-value, exactly like bash:

- `"..."` strips the surrounding double quotes; the contents are expanded.
- `'...'` strips the surrounding single quotes; the contents are taken literally — no `$`, no `~`, no escapes.

```
"hi $USER"             → hi nawa
'$NOT_EXPANDED'        → $NOT_EXPANDED
prefix"$VAR"suffix     → prefixVALUEsuffix
```

An unterminated `"` or `'` is a parse error.

### Escapes

Outside quotes and inside `"..."`:

| Escape | Becomes |
|---|---|
| `\$` | `$` |
| `\\` | `\` |
| `\"` | `"` |
| `\~` | `~` |
| `\'` | `'` (outside quotes only) |
| `\` + any other char | literal `\` followed by the char |

Inside `'...'` there are no escapes — every character including `\` is taken literally.

`\n`, `\t`, etc. inside `"..."` are **not** interpreted as control characters; they are the literal two-character sequences `\` `n` and `\` `t`. (Bash's `$'...'` form, which interprets those, is not supported.)

### `.env` line format

- Comments: a full-line `#` (with optional leading whitespace) is skipped. A `#` mid-line is **not** a comment — it is part of the value.
- Blank lines are skipped.
- Otherwise the line must match `KEY=VALUE`:
  - `KEY` matches `[A-Za-z_][A-Za-z0-9_]*`.
  - No whitespace is allowed around the `=`.
  - An optional `export ` prefix on the line is accepted and stripped.
- Bare keys without `=` are a parse error. To pass a variable through from the host environment, write the explicit form `KEY=$KEY` (or `KEY=${KEY:-}` if missing is OK).
- Trailing whitespace on an unquoted value is stripped. Trailing whitespace inside `"..."` or `'...'` is preserved.
- CRLF line endings are tolerated (`\r` at end-of-line is stripped silently).
- Multi-line values are **not** supported.
- Earlier lines are visible to later lines (bash `source`-style scope):

```
USER_NAME=cody
GREETING=Hi $USER_NAME      # → Hi cody
```

When a name is not yet defined locally, the lookup falls through to the host environment, so:

```
PATH=$PATH:/extra           # PATH from host, with /extra appended
VAR1=$VAR1                  # passthrough — VAR1 from host environment
```

### Scope between sources

Each source is expanded independently against the host environment. `.env` does not see values defined in `config.toml`, and `config.toml` does not see values defined in `.env`. When both `.booth/.env` and an explicit `--env-file` are present, docker merges them on its side (last wins on conflict).

### Recursion

Nested defaults are allowed: `${A:-${B:-fallback}}`. Recursion depth is capped at 32; deeper expansions are a parse error.

### Errors

Every parse or expansion failure aborts booth with a non-zero exit code **before** docker is invoked. No partial state, no temp files left behind. Messages are source-located:

```
.booth/.env:12: required variable DATABASE_URL is not set
config.toml: run-args[3]: unterminated double-quote
CB_RUN_ARGS: unsupported operator in ${X:=y} (only :- and :? are supported)
```

---

## How `.env` actually flows to docker

1. Booth reads `.booth/.env` (and an explicit `--env-file <path>` if configured).
2. Each line is parsed; values are expanded against a running scope that starts empty and grows with each accepted line, falling through to the host environment on miss.
3. The expanded `KEY=VALUE` pairs are written to a temp file under `.booth/.tmp/env-*.expanded` with mode `0600`.
4. Booth passes that temp file to docker via `--env-file`. Docker's native `--env-file` is then a literal pass-through, which is exactly what we want now.
5. The temp file is cleaned up at the end of the run (along with everything else in `.booth/.tmp/`, unless `--leave-tmp-on-exit` is set).

In `--dryrun` mode the temp file is **not** written — booth still parses and validates the file (so `${VAR:?}` and parse errors surface), but the printed docker invocation references the original path so the dryrun output is stable.

---

## Worked examples

```bash
# .booth/.env
HOME_BACKUP=~/backups
GREETING="Hi $USER"
LITERAL='$NOT_EXPANDED'
PRICE=\$100
PORT=${APP_PORT:-8080}
DB_URL=${DATABASE_URL:?required for app boot}
PATH=$PATH:/opt/tools
```

Resolved (when `HOME=/home/nawa`, `USER=nawa`, `APP_PORT` unset, `DATABASE_URL` set to `postgres://…`):

```
HOME_BACKUP=/home/nawa/backups
GREETING=Hi nawa
LITERAL=$NOT_EXPANDED
PRICE=$100
PORT=8080
DB_URL=postgres://…
PATH=/usr/bin:/bin:/opt/tools
```

If `DATABASE_URL` is unset, booth aborts:

```
.booth/.env:6: required for app boot
```

```toml
# .booth/config.toml
image    = "~/.cache/codingbooth/img"
run-args = [
  "-e", "WORKSPACE=$HOME/work",
  "-e", "LITERAL='$KEEP_AS_IS'",
  "-e", "REGION=${AWS_REGION:-us-east-1}",
]
```

```bash
# CLI — the invoking shell handles expansion. Booth does not double-expand.
booth run -e PATH_THING="$HOME/bin"     # shell expands $HOME
booth run -e LITERAL='$KEEP'            # shell keeps $KEEP literal; booth passes through
```

---

## Out of scope

- Multi-line `.env` values. Docker's `--env-file` does not support them, and keeping things single-line lets booth keep using `--env-file` rather than a sourced-script entrypoint.
- Bash forms beyond `:-` and `:?` (`:=`, `:+`, `#`/`##`, `%`/`%%`, substring, case, replacement, length, indirection).
- Command substitution `$(...)` and backticks — permanently unsupported, by design. Running bash on configuration content would introduce arbitrary code execution. The supported subset gives `${VAR:-default}` and `${VAR:?error}` semantics without the safety hit.
- Expansion of CLI `-e` / `--env` flags. The shell already did its job by the time booth sees argv; a second pass would surprise users.
