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
| `tools/grok`           | Grok (xAI)       |
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

### Order 70 — Notebook kernels (need notebook/Jupyter)

| Extension                    | Display Name           |
|------------------------------|------------------------|
| `clang/kernel--extension`    | C++ Notebook Kernel (xeus-cling, experimental) |
| `education/nbgrader`         | nbgrader               |
| `go/kernel--extension`       | Go Notebook Kernel     |
| `haskell/kernel--extension`  | Haskell Notebook Kernel |
| `java/kernel--extension`     | Java Notebook Kernel   |
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
