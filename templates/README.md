# Template Authoring Guidelines

## Segment Ordering

When a template's `[segments]` section defines Boothfile content, the segment key controls
the order in the final generated Boothfile. All segments from all selected templates are
merged **globally** and sorted by order number, with alphabetical tiebreak by template name.

| Segment Key        | Order | Use for                                                                                       |
|--------------------|-------|-----------------------------------------------------------------------------------------------|
| `"Boothfile--40"`  | 40    | Infrastructure (desktop environments: xfce, kde, lxqt)                                        |
| `Boothfile`        | 50    | Base/independent setups (languages, tools, databases)                                         |
| `"Boothfile--60"`  | 60    | Dependent setups (IDEs: codeserver/vscode; notebook; derived languages: kotlin, scala, etc.)  |
| `"Boothfile--65"`  | 65    | Language VS Code extensions (need codeserver/vscode from order 60)                            |
| `"Boothfile--70"`  | 70    | Notebook kernels (need notebook from order 60)                                                |
| `"Boothfile--90"`  | 90    | Post-setup steps (pip/uv/conda install from requirements.txt, etc.)                           |

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

## Run Args & Persistent Volumes

Templates can specify `run-args` to add Docker flags when the container starts.
A common use case is **persistent volumes** for databases so data survives container restarts.

```toml
# Named Docker volume — data persists across container restarts
run-args = [
    "-v", "booth-pgdata:/var/lib/postgresql",
]
```

### Database Volume Conventions

| Database   | Volume Name        | Mount Point            |
|------------|--------------------|------------------------|
| PostgreSQL | `booth-pgdata`     | `/var/lib/postgresql`  |
| MySQL      | `booth-mysqldata`  | `/var/lib/mysql`       |

These use **named Docker volumes** (not bind mounts), so Docker manages the storage.
Data persists even if the container is removed, as long as the volume exists.

To reset a database: `docker volume rm booth-pgdata` (or `booth-mysqldata`).

### Other Run Args Uses

- **Credential seeding**: mount host config files as read-only into `/etc/cb-home-seed/`
- **Environment variables**: `-e`, `"VAR=value"` for runtime configuration
- **Port publishing**: `-p`, `"host:container"` for exposing services

> **Careful with TOML scoping.** `run-args` is a top-level key, so it must appear *before* any
> `[params.X]` or `[segments]` table header. Put it after one and TOML reads it as a key of that
> table (`params.X.run-args`) — the loader finds no top-level `run-args` and the flags are silently
> dropped. The template still compiles; the port just never gets published.

## Server Templates: Auto-Start & Expose

A template that installs a **server** — something that listens on a port — should not start it or
publish it on its own. Both are opt-in extensions, so a booth that merely *has* the tool doesn't
pay for a daemon it isn't using.

The convention is two extensions beside the parent, which declares the port as a param:

| File                       | `display-order` | Does                                                    |
|----------------------------|-----------------|---------------------------------------------------------|
| `expose--extension.toml`   | 1               | `run-args = ["-p", "${X_HOST_PORT}:${X_PORT}"]` — reach it from the host |
| `autostart--extension.toml`| 2               | a `"startup--65.sh"` segment that `nohup`s the server    |

Both are `auto-select = false`. `${X_PORT}` in a startup segment compiles to `${X_PORT:-<default>}`,
so the port stays overridable at runtime; in `run-args` it compiles to the literal value.

### Two ports, two params

`X_PORT` (on the parent) is the port the server **listens on**; `X_HOST_PORT` (on the `expose`
extension) is the port it is **published on**. The host one defaults to a *reference*, so it follows
the service and the two cannot drift apart:

```toml
# tools/cloudbeaver/expose--extension.toml
run-args = [
    "-p", "${CLOUDBEAVER_HOST_PORT}:${CLOUDBEAVER_PORT}",
]

# Host-side port. Defaults to the port the service listens on, so moving the service
# moves the published port with it. Override only when the host port is already taken.
[params.CLOUDBEAVER_HOST_PORT]
default = "${CLOUDBEAVER_PORT}"
```

`cloudbeaver:25.3.5,9000+expose` then publishes `9000:9000`, and `+expose:19000` publishes
`19000:9000`. Do **not** hardcode the host port: an earlier round of these extensions published a
literal `8978`/`2222`, so moving the service port served the tool on one port and published another
— nothing was listening on the port that got published.

A host port may also be given as `+OFFSET`, which is **relative to the booth port**: it stays in
`run-args` as `"-p", "+4567:5672"` and is resolved at container start as `boothPort + OFFSET`
(`ResolveRelativePorts`). `rabbitmq+start+expose:+4567` on a booth at 20000 publishes AMQP on 24567.
Nothing is needed in the template for this — the compiler substitutes the param value verbatim, so
any host-port param accepts it. It is the host side only; a `+OFFSET` on the container side would
tell the server to listen on a port that does not exist.

A param default may reference any other param by name, resolved transitively before use; a cycle is
a config-time error. A `${NAME}` that is not a param (`${HOME}`) is passed through for the shell.

A server whose setup script hardcodes its listening port (`postgresql` is always 5432 inside the
container) has no `X_PORT` at all — its `expose` extension carries the host port alone, and the
container side is the literal: `"-p", "${POSTGRES_PORT}:5432"`.

```toml
# tools/excalidraw/autostart--extension.toml
[segments]
"startup--65.sh" = """
PORT=${EXCALIDRAW_PORT}
LOG_FILE="/tmp/excalidraw.log"

nohup serve -s --no-clipboard /opt/excalidraw -l "$PORT" > "$LOG_FILE" 2>&1 &

echo "Excalidraw started on port $PORT (PID $!, log: $LOG_FILE)"
"""
```

### Guard when the server is also a variant's primary service

`notebook` and `codeserver` are both a template *and* a variant. On their own variant the server is
already running as the primary service — and on the **same port** the template defaults to (JupyterLab
on 18888, code-server on 19999, each fronted by the booth's nginx). Auto-starting a second one there
is not merely redundant, it collides. So the startup segment must bail out on the matching variant:

```bash
if [ "${BOOTH_VARIANT_TAG:-base}" = "notebook" ]; then
  echo "JupyterLab is the primary service of the notebook variant — auto-start skipped."
else
  ...
fi
```

`BOOTH_VARIANT_TAG` is passed into every container as the canonical variant name, so this is the
test to use whenever a template's behavior depends on which UI the booth is running.

### When the setup script already auto-starts

Some servers (`nginx`, `apache`, `postgresql`, `mysql`, `redis`, `mongodb`) install their own hook
into `/usr/share/startup.d/` at build time and come up on every boot. Those need **no** `autostart`
extension — only `expose`, since the daemon is still unreachable from the host without a published
port. Check the setup script for a `/usr/share/startup.d/` write before adding one.

## Template Reference

All templates and extensions grouped by segment order.

### Order 40 — Infrastructure (desktop environments)

| Template         | Display Name |
|------------------|--------------|
| `desktops/kde`   | KDE Plasma   |
| `desktops/lxqt`  | LXQt         |
| `desktops/xfce`  | XFCE         |

### Order 50 — Base setups (languages, tools, databases)

| Template               | Display Name     |
|------------------------|------------------|
| `databases/mysql`      | MySQL            |
| `databases/postgresql` | PostgreSQL       |
| `databases/sqlite`     | SQLite           |
| `languages/bun`        | Bun              |
| `languages/clang`      | Clang (C/C++)    |
| `languages/deno`       | Deno             |
| `languages/erlang`     | Erlang           |
| `languages/fpc`        | Free Pascal      |
| `languages/gcc`        | GCC (C/C++)      |
| `languages/go`         | Go               |
| `languages/haskell`    | Haskell          |
| `languages/java`       | Java             |
| `languages/lua`        | Lua              |
| `languages/nodejs`     | Node.js          |
| `languages/php`        | PHP              |
| `languages/python`     | Python           |
| `languages/r`          | R                |
| `languages/ruby`       | Ruby             |
| `languages/rust`       | Rust             |
| `languages/zig`        | Zig              |
| `tools/aws-cli`        | AWS CLI          |
| `tools/build-essential`| Build Essentials |
| `tools/claude-code`    | Claude Code      |
| `ai-tools/opencode`    | OpenCode         |
| `ai-tools/gemini-cli`  | Gemini CLI       |
| `ai-tools/grok`        | Grok Build (xAI) |
| `ai-tools/oh-my-pi`    | Oh My Pi (omp)   |
| `ai-tools/goose`       | Goose            |
| `tools/herdr`          | Herdr (agent multiplexer) |
| `tools/cmake`          | CMake            |
| `tools/conan`          | Conan            |
| `tools/dind`           | Docker-in-Docker |
| `tools/docker-buildx`  | Docker Buildx    |
| `tools/docker-compose` | Docker Compose   |
| `tools/firebase`       | Firebase CLI     |
| `tools/gcloud`         | Google Cloud SDK |
| `tools/gh`             | GitHub CLI       |
| `tools/homebrew`       | Homebrew         |
| `tools/kind`           | kind             |
| `tools/make`           | GNU Make         |
| `tools/neovim`         | Neovim           |
| `tools/openssh`        | OpenSSH Client   |
| `tools/vhs`            | VHS (terminal/TUI recorder) |

### Order 50 — Extensions (run alongside parent)

| Extension                  | Display Name                  |
|----------------------------|-------------------------------|
| `gh/copilot--extension`    | GitHub Copilot CLI            |
| `go/linter--extension`     | Go Linter                     |
| `openssh/server--extension`| OpenSSH Server                |
| `openssh/credential--extension` | SSH Credentials          |
| `openssh/expose--extension`| Expose SSH Port               |
| `java/gradle--extension`   | Gradle                        |
| `java/jbang--extension`    | jbang Warm Cache              |
| `java/jenv--extension`     | jenv                          |
| `java/maven--extension`    | Maven                         |
| `python/conda--extension`  | Conda *(also has order 90)*   |
| `python/uv--extension`     | uv *(also has order 90)*      |

### Order 60 — Dependent setups (IDEs, browsers, desktop apps, derived languages)

| Template                  | Display Name     |
|---------------------------|------------------|
| `browsers/chromium`       | Chromium         |
| `browsers/firefox`        | Firefox          |
| `browsers/google-chrome`  | Google Chrome    |
| `desktops/gimp`           | GIMP             |
| `desktops/inkscape`       | Inkscape         |
| `desktops/libreoffice`    | LibreOffice      |
| `education/bluej`         | BlueJ            |
| `education/drracket`      | DrRacket         |
| `education/exercism`      | Exercism CLI     |
| `education/greenfoot`     | Greenfoot        |
| `education/scratch`       | Scratch          |
| `education/thonny`        | Thonny           |
| `ides/clion`              | CLion            |
| `ides/codeserver`         | code-server      |
| `ides/datagrip`           | DataGrip         |
| `ides/eclipse`            | Eclipse          |
| `ides/goland`             | GoLand           |
| `ides/idea`               | IntelliJ IDEA    |
| `ides/phpstorm`           | PhpStorm         |
| `ides/pycharm`            | PyCharm          |
| `ides/rider`              | Rider            |
| `ides/rubymine`           | RubyMine         |
| `ides/vscode`             | VS Code          |
| `ides/webstorm`           | WebStorm         |
| `languages/clojure`       | Clojure          |
| `languages/elixir`        | Elixir           |
| `languages/kotlin`        | Kotlin           |
| `languages/scala`         | Scala            |
| `tools/codex`             | Codex            |
| `tools/notebook`          | Jupyter Notebook |
| `tools/warp`              | Warp             |

### Order 65 — Language VS Code extensions (need codeserver/vscode)

| Extension                         | Display Name                  |
|-----------------------------------|-------------------------------|
| `bun/vscode-ext--extension`       | Bun VS Code Extension         |
| `clang/vscode-ext--extension`     | Clang VS Code Extension       |
| `clojure/vscode-ext--extension`   | Clojure VS Code Extension     |
| `deno/vscode-ext--extension`      | Deno VS Code Extension        |
| `elixir/vscode-ext--extension`    | Elixir VS Code Extension      |
| `erlang/vscode-ext--extension`    | Erlang VS Code Extension      |
| `fpc/vscode-ext--extension`       | Free Pascal VS Code Extension |
| `gcc/vscode-ext--extension`       | GCC VS Code Extension         |
| `go/vscode-ext--extension`        | Go VS Code Extension          |
| `haskell/vscode-ext--extension`   | Haskell VS Code Extension     |
| `java/vscode-ext--extension`      | Java VS Code Extension        |
| `kotlin/vscode-ext--extension`    | Kotlin VS Code Extension      |
| `lua/vscode-ext--extension`       | Lua VS Code Extension         |
| `nodejs/vscode-ext--extension`    | Node.js VS Code Extension     |
| `php/vscode-ext--extension`       | PHP VS Code Extension         |
| `python/vscode-ext--extension`    | Python VS Code Extension      |
| `r/vscode-ext--extension`         | R VS Code Extension           |
| `ruby/vscode-ext--extension`      | Ruby VS Code Extension        |
| `rust/vscode-ext--extension`      | Rust VS Code Extension        |
| `scala/vscode-ext--extension`     | Scala VS Code Extension       |
| `zig/vscode-ext--extension`       | Zig VS Code Extension         |
| `ides/code-ext-pkg`               | VS Code Extensions *(any id — top-level template, not a `+ext`)* |

Each `<lang>/vscode-ext--extension` pins one known-good extension id for its
language and compiles to `setup <lang>-code-extension`. `ides/code-ext-pkg` is the
escape hatch beside them: a variadic list of arbitrary Open VSX ids compiling to
`install code-extension <ids>`. Add a curated extension when a language has an
obvious one — a user shouldn't have to know an id to get a working editor — and
leave `code-ext-pkg` for the long tail.

`code-ext-pkg` is a **top-level template, not an extension of `codeserver`**, and
deliberately so: an editor is not always supplied by that template. `code-server`
comes from the `codeserver` variant, and desktop VS Code is baked into all four
desktop variants (`RUN vscode--setup.sh` in each of their Dockerfiles) — in neither
case is the `codeserver` template selected. Hanging the id list off it would force
users on a desktop variant to install a second, browser-based editor just to name an
extension. Both installers instead resolve at build time: `cb-has-vscode.sh` for
presence, then install into whichever of `code` / `code-server` exists — both, when
both do. Same reason the curated `<lang>/vscode-ext` extensions work unchanged on
codeserver and desktop alike.

#### The two editors do not share a registry

This is the trap to know about before writing a `*-code-extension--setup.sh`:

| Editor | Registry | Ships with |
|--------|----------|------------|
| code-server | [Open VSX](https://open-vsx.org) | the `codeserver` variant |
| desktop VS Code | [Microsoft Marketplace](https://marketplace.visualstudio.com) | all four desktop variants |

The publisher namespaces are independent, so **the same extension often has a
different id on each**, and an id can be missing from one — or, worse, resolve there
to a different package. ElixirLS is both:

| id | Open VSX | Marketplace |
|----|----------|-------------|
| `elixir-lsp.elixir-ls` | ElixirLS 0.31.1 ✅ | "ElixirLS Fork: **DEPRECATED**" 0.3.9999 ❌ |
| `JakeBecker.elixir-ls` | — ❌ | ElixirLS 0.31.1 ✅ |

So the lib offers three entry points; pick by where the id resolves:

```bash
install_extensions             mads-hartmann.bash-ide-vscode  # same id on both
install_codeserver_extensions  elixir-lsp.elixir-ls           # Open VSX id
install_vscode_extensions      JakeBecker.elixir-ls           # Marketplace id
```

The per-editor calls are quiet no-ops when that editor isn't in the image, so they
are safe on every variant. Marketplace-only extensions (`ms-dotnettools.csharp`,
`ms-vscode.cpptools`, `visualstudioexptteam.vscodeintellicode` — all
Microsoft-licensed) belong in `install_vscode_extensions`; that leaves code-server
without them, which is a real gap tracked in `docs/TODO.md`.

Verify a new id on **both** registries before adding it — a failed install only
warns, so a wrong id yields an image quietly missing the extension, and a
wrong-but-resolving id yields one carrying the wrong package:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://open-vsx.org/api/<pub>/<name>
curl -s -X POST https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json;api-version=3.0-preview.1' \
  -d '{"filters":[{"criteria":[{"filterType":7,"value":"<pub>.<name>"}]}],"flags":914}'
```

### Order 70 — Notebook kernels (need notebook/Jupyter)

| Extension                    | Display Name           |
|------------------------------|------------------------|
| `clang/kernel--extension`    | C++ Notebook Kernel (xeus-cling, experimental) |
| `education/nbgrader`         | nbgrader               |
| `go/kernel--extension`       | Go Notebook Kernel     |
| `haskell/kernel--extension`  | Haskell Notebook Kernel |
| `java/kernel--extension`     | Java Notebook Kernel (IJava) |
| `java/kernel-jjava--extension` | Java Notebook Kernel (JJava, Java 11+) — pick this *or* `java/kernel`, not both |
| `kotlin/kernel--extension`   | Kotlin Notebook Kernel |
| `nodejs/kernel--extension`   | Node.js Notebook Kernel |
| `python/kernel--extension`   | Python Notebook Kernel |
| `r/kernel--extension`        | R Notebook Kernel      |
| `ruby/kernel--extension`     | Ruby Notebook Kernel   |
| `rust/kernel--extension`     | Rust Notebook Kernel   |

### Order 60 — Package manager extensions (global package installation)

| Extension                       | Display Name     |
|---------------------------------|------------------|
| `bun/bun-pkg--extension`        | bun Packages     |
| `conan/conan-pkg--extension`    | Conan Packages   |
| `elixir/hex-pkg--extension`     | Hex Packages     |
| `go/go-pkg--extension`          | Go Packages      |
| `haskell/cabal-pkg--extension`  | Cabal Packages   |
| `lua/luarocks-pkg--extension`   | LuaRocks Packages|
| `nodejs/npm-pkg--extension`     | npm Packages     |
| `nodejs/yarn-pkg--extension`    | Yarn Packages    |
| `php/pecl-pkg--extension`       | PECL Packages    |
| `python/conda-pkg--extension`   | Conda Packages   |
| `python/pip-pkg--extension`     | pip Packages     |
| `python/uv-pkg--extension`      | uv Packages      |
| `ruby/gem-pkg--extension`       | Gem Packages     |
| `rust/cargo-pkg--extension`     | Cargo Packages   |
| `tools/brew-pkg`                | brew Packages    |

### Order 90 — Post-setup steps

| Extension                             | Display Name              |
|---------------------------------------|---------------------------|
| `python/conda--extension`             | Conda                     |
| `python/pip--extension`               | pip requirements          |
| `python/uv--extension`                | uv                        |

### Order 90 — Dependency pre-installation (from manifest files)

| Extension                             | Display Name              |
|---------------------------------------|---------------------------|
| `bun/bun-install--extension`          | bun install               |
| `elixir/mix-deps--extension`          | Mix Dependencies          |
| `go/go-mod--extension`                | Go Modules                |
| `java/gradle-deps--extension`         | Gradle Dependencies       |
| `java/mvn-install--extension`         | Maven Dependencies        |
| `nodejs/npm-install--extension`       | npm install               |
| `nodejs/pnpm-install--extension`      | pnpm install              |
| `nodejs/yarn-install--extension`      | Yarn install              |
| `php/composer-install--extension`     | Composer install          |
| `ruby/bundle-install--extension`      | Bundle install            |
| `rust/cargo-build--extension`         | Cargo Build               |
