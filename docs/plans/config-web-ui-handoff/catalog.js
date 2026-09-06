/* Catalog derived from NawaMan/CodingBooth@main templates/ (153 templates, 207 extensions).
   Names, categories, requires, params, unsupported-arch and extension lists are taken from the
   repo's template.toml / *--extension.toml files. Descriptions are the repo's display-disc where
   read; templates read in bulk carry name + category + extensions only. */
(function () {
  // Extension families the repo documents in templates/README.md.
  var FAM = {
    'expose':        { s: 'Publish this service to the host. Host port param; container port comes from the parent.' },
    'autostart':     { s: 'Start the server on container boot (startup--65.sh). Off by default — a booth that merely has the tool should not pay for a daemon.' },
    'start':         { s: 'Start the server on container boot. Off by default.' },
    'vscode-ext':    { s: 'The curated editor extension for this language. Needs an editor in the image.', a: 1, needs: 'editor' },
    'kernel':        { s: 'Register this language as a Jupyter kernel.', req: ['notebook'] },
    'credential':    { s: 'Mount the host credential store read-only into the home seed, so the booth is already signed in.' },
    'settings-cache':{ s: 'Keep this tool\u2019s settings in a cache path so they survive rebuilds.' },
    'plugins':       { s: 'Plugins or MCP servers to register for this agent.' },
    'repl-history':  { s: 'Persist REPL history across container restarts.' },
    'cli-history':   { s: 'Persist the client\u2019s shell history across restarts.' },
    'profile-cache': { s: 'Keep the browser profile in a cache path across rebuilds.' }
  };
  function famOf(n) {
    if (FAM[n]) return FAM[n];
    if (/-pkg$/.test(n)) return { s: 'Global packages installed at build. Variadic list \u2014 one requirement per entry.', list: 1 };
    if (/-install$|-deps$|-build$/.test(n)) return { s: 'Pre-install this project\u2019s dependencies from its manifest at build time (order 90).' };
    if (/-shared$/.test(n)) return { s: 'Share this state with the host through a shared path.' };
    if (/-cache$/.test(n)) return { s: 'Keep this state in a cache path across rebuilds.' };
    if (/^config/.test(n)) return { s: 'Seed this tool\u2019s configuration from the host.' };
    return { s: '' };
  }

  // Host-port-only expose extensions: the setup script hardcodes the listening port.
  var FIXED = { postgresql: ['POSTGRES_PORT', '5432'], mysql: ['MYSQL_PORT', '3306'],
    mongodb: ['MONGO_PORT', '27017'], redis: ['REDIS_HOST_PORT', '6379'],
    nginx: ['NGINX_HOST_PORT', '80'], apache: ['APACHE_HOST_PORT', '80'],
    openssh: ['SSH_HOST_PORT', '22'], rabbitmq: ['RABBITMQ_HOST_PORT', '5672'] };
  // Expose extensions whose host port follows a parent port param.
  var FOLLOWS = { codeserver: 'CODESERVER_PORT', notebook: 'NOTEBOOK_PORT', cloudbeaver: 'CLOUDBEAVER_PORT',
    ollama: 'OLLAMA_PORT', kafka: 'KAFKA_PORT', excalidraw: 'EXCALIDRAW_PORT', mermaid: 'MERMAID_PORT',
    plantuml: 'PLANTUML_PORT', scratch: 'SCRATCH_PORT' };

  var P = function (k, d, sug) { return { k: k, d: d, sug: sug || [] }; };
  var L = function (k, hint, ph) { return { k: k, d: '', list: { k: k, hint: hint, ph: ph || 'add an entry, Enter to commit' } }; };

  // n=name c=category dn=display-name s=display-disc p=primary t=tags req=requires
  // needs=variant assumption arch=unsupported-arch dind params exts
  var T = [
    // ── ai-tools ────────────────────────────────────────────────────────────
    { n: 'claude-code', c: 'ai-tools', dn: 'Claude Code', p: 1, s: 'Anthropic Claude Code AI coding assistant', t: ['ai', 'claude'],
      params: [P('CLAUDE_CODE_VERSION', 'latest', ['latest'])], exts: ['auto-accept', 'credential', 'settings-cache'] },
    { n: 'codex', c: 'ai-tools', dn: 'Codex', t: ['ai'], exts: ['credential'] },
    { n: 'aider', c: 'ai-tools', dn: 'Aider', t: ['ai'], exts: [] },
    { n: 'antigravity', c: 'ai-tools', dn: 'Antigravity', t: ['ai'], exts: ['credential'] },
    { n: 'cursor', c: 'ai-tools', dn: 'Cursor', t: ['ai'], exts: ['credential'] },
    { n: 'gemini-cli', c: 'ai-tools', dn: 'Gemini CLI', t: ['ai'], exts: ['credential', 'plugins', 'settings-cache'] },
    { n: 'gh-copilot', c: 'ai-tools', dn: 'GitHub Copilot CLI', t: ['ai'], exts: [] },
    { n: 'goose', c: 'ai-tools', dn: 'Goose', t: ['ai'], exts: ['credential', 'plugins', 'settings-cache'] },
    { n: 'grok', c: 'ai-tools', dn: 'Grok Build (xAI)', t: ['ai'], exts: ['credential', 'plugins', 'settings-cache'] },
    { n: 'herdr', c: 'ai-tools', dn: 'Herdr (agent multiplexer)', t: ['ai'], exts: ['autostart'] },
    { n: 'oh-my-pi', c: 'ai-tools', dn: 'Oh My Pi (omp)', t: ['ai'], exts: ['credential', 'plugins', 'settings-cache'] },
    { n: 'opencode', c: 'ai-tools', dn: 'OpenCode', t: ['ai'], exts: ['credential', 'plugins', 'settings-cache'] },
    { n: 'warp', c: 'ai-tools', dn: 'Warp', t: ['ai'], exts: ['credential'] },
    { n: 'ollama', c: 'ai-tools', dn: 'Ollama', s: 'Run large language models locally with Ollama', t: ['ai', 'llm', 'ollama', 'local'],
      params: [P('OLLAMA_PORT', '11434', ['11434']), P('OLLAMA_VERSION', 'latest', ['latest'])], exts: ['autostart', 'expose'] },

    // ── browsers ────────────────────────────────────────────────────────────
    { n: 'chromium', c: 'browsers', dn: 'Chromium', s: 'Chromium browser for web testing (no snap)', t: ['browser', 'chromium', 'web'], needs: 'desktop',
      exts: ['bookmarks-shared', 'extensions-shared', 'managed-policies', 'profile-cache', 'settings-shared'] },
    { n: 'firefox', c: 'browsers', dn: 'Firefox', t: ['browser', 'web'], needs: 'desktop',
      exts: ['bookmarks-shared', 'extensions-shared', 'managed-policies', 'profile-cache', 'settings-shared'] },
    { n: 'google-chrome', c: 'browsers', dn: 'Google Chrome', s: 'Google Chrome browser for web testing (DEB repo)', t: ['browser', 'chrome', 'web'], needs: 'desktop',
      arch: { on: 'arm64', use: 'chromium (same engine, arm64 build, provides a google-chrome command) or firefox' },
      exts: ['bookmarks-shared', 'extensions-shared', 'managed-policies', 'profile-cache', 'settings-shared'] },

    // ── databases ───────────────────────────────────────────────────────────
    { n: 'postgresql', c: 'databases', dn: 'PostgreSQL', s: 'PostgreSQL database with persistent volume', t: ['database', 'postgresql', 'sql'],
      params: [P('PG_VERSION', 'latest', ['latest'])], exts: ['cli-history', 'expose'] },
    { n: 'mysql', c: 'databases', dn: 'MySQL', t: ['database', 'sql'], exts: ['cli-history', 'expose'] },
    { n: 'mongodb', c: 'databases', dn: 'MongoDB', t: ['database'], exts: ['cli-history', 'expose'] },
    { n: 'redis', c: 'databases', dn: 'Redis', s: 'Redis in-memory store with persistent volume', t: ['database', 'redis', 'cache'],
      params: [P('REDIS_VERSION', 'latest', ['latest'])], exts: ['cli-history', 'expose'] },
    { n: 'sqlite', c: 'databases', dn: 'SQLite', t: ['database', 'sql'], exts: ['cli-history'] },
    { n: 'kafka', c: 'databases', dn: 'Kafka', s: 'Apache Kafka single-node KRaft broker', t: ['kafka', 'messaging', 'streaming', 'apache'],
      params: [P('KAFKA_VERSION', '3.7.0', ['3.7.0', '3.6.1', '3.5.2']), P('KAFKA_PORT', '9092', ['9092', '19092'])], exts: ['expose', 'start'] },
    { n: 'rabbitmq', c: 'databases', dn: 'RabbitMQ', t: ['messaging'], exts: ['expose', 'start'] },

    // ── desktops ────────────────────────────────────────────────────────────
    { n: 'xfce', c: 'desktops', dn: 'XFCE', s: 'XFCE lightweight desktop with VNC/noVNC access', t: ['desktop', 'xfce', 'lightweight', 'vnc'],
      exts: ['desktop-icons-cache', 'desktop-icons-shared', 'keyboard-shortcuts-shared'] },
    { n: 'kde', c: 'desktops', dn: 'KDE Plasma', t: ['desktop'], exts: [] },
    { n: 'lxqt', c: 'desktops', dn: 'LXQt', t: ['desktop'], exts: ['desktop-icons-cache', 'desktop-icons-shared'] },
    { n: 'wayland', c: 'desktops', dn: 'Wayland', t: ['desktop'], exts: [] },
    { n: 'gimp', c: 'desktops', dn: 'GIMP', t: ['desktop', 'gui'], needs: 'desktop', exts: [] },
    { n: 'inkscape', c: 'desktops', dn: 'Inkscape', t: ['desktop', 'gui'], needs: 'desktop', exts: [] },
    { n: 'libreoffice', c: 'desktops', dn: 'LibreOffice', t: ['desktop', 'gui'], needs: 'desktop', exts: [] },

    // ── education ───────────────────────────────────────────────────────────
    { n: 'thonny', c: 'education', dn: 'Thonny', s: 'Beginner-friendly Python IDE (requires desktop variant)', t: ['education', 'python', 'ide', 'beginner', 'desktop'],
      req: ['python'], needs: 'desktop', exts: [] },
    { n: 'nbgrader', c: 'education', dn: 'nbgrader', s: 'Jupyter assignment creation & auto-grading (requires notebook)', t: ['education', 'jupyter', 'notebook', 'grading', 'classroom'],
      req: ['notebook'], exts: [] },
    { n: 'bluej', c: 'education', dn: 'BlueJ', t: ['education', 'java'], needs: 'desktop', exts: [] },
    { n: 'greenfoot', c: 'education', dn: 'Greenfoot', t: ['education', 'java'], needs: 'desktop', exts: [] },
    { n: 'drracket', c: 'education', dn: 'DrRacket', t: ['education'], needs: 'desktop', exts: [] },
    { n: 'exercism', c: 'education', dn: 'Exercism CLI', t: ['education'], exts: [] },
    { n: 'scratch', c: 'education', dn: 'Scratch', t: ['education'], exts: ['autostart', 'expose'] },

    // ── ides ────────────────────────────────────────────────────────────────
    { n: 'codeserver', c: 'ides', dn: 'code-server', s: 'Browser-based VS Code IDE via code-server', t: ['vscode', 'codeserver', 'ide', 'web'],
      params: [P('CODESERVER_PORT', '19999', ['19999', '8443'])],
      exts: ['autostart', 'expose', 'keybindings-shared', 'settings-cache', 'settings-shared', 'snippets-shared'] },
    { n: 'code-ext-pkg', c: 'ides', dn: 'VS Code Extensions', s: 'Install any VS Code / code-server extension by marketplace id. Top-level template, not a child of codeserver: the editor comes from the variant.',
      t: ['vscode', 'codeserver', 'extensions', 'ide', 'packages'], needs: 'editor',
      params: [L('CODE_EXT_PKGS', 'Open VSX id, @version pins one \u2014 eamodio.gitlens@15.6.0', 'add a marketplace id, Enter to commit')], exts: [] },
    { n: 'jetbrains-plugin-pkg', c: 'ides', dn: 'JetBrains Plugins', s: 'Install any JetBrains IDE plugin by marketplace id. Needs a JetBrains IDE, so a desktop variant.',
      t: ['jetbrains', 'plugins', 'ide', 'packages'], needs: 'desktop',
      params: [L('JETBRAINS_PLUGIN_PKGS', 'xmlId or the number from the plugin URL \u2014 IdeaVIM, 6317, IdeaVIM@2.31.0', 'add a plugin id, Enter to commit')], exts: [] },
    { n: 'idea', c: 'ides', dn: 'IntelliJ IDEA', s: 'JetBrains IntelliJ IDEA Community for Java/Kotlin', t: ['jetbrains', 'idea', 'ide', 'java'], needs: 'desktop',
      exts: ['jdk-sdk', 'lombok', 'skip-first-run'] },
    { n: 'pycharm', c: 'ides', dn: 'PyCharm', t: ['jetbrains', 'ide'], needs: 'desktop', exts: [] },
    { n: 'goland', c: 'ides', dn: 'GoLand', t: ['jetbrains', 'ide'], needs: 'desktop', exts: [] },
    { n: 'clion', c: 'ides', dn: 'CLion', t: ['jetbrains', 'ide'], needs: 'desktop', exts: [] },
    { n: 'phpstorm', c: 'ides', dn: 'PhpStorm', t: ['jetbrains', 'ide'], needs: 'desktop', exts: [] },
    { n: 'rider', c: 'ides', dn: 'Rider', t: ['jetbrains', 'ide'], needs: 'desktop', exts: [] },
    { n: 'rubymine', c: 'ides', dn: 'RubyMine', t: ['jetbrains', 'ide'], needs: 'desktop', exts: [] },
    { n: 'webstorm', c: 'ides', dn: 'WebStorm', t: ['jetbrains', 'ide'], needs: 'desktop', exts: [] },
    { n: 'datagrip', c: 'ides', dn: 'DataGrip', t: ['jetbrains', 'database', 'ide'], needs: 'desktop', exts: [] },
    { n: 'eclipse', c: 'ides', dn: 'Eclipse', t: ['ide', 'java'], needs: 'desktop', exts: [] },
    { n: 'dbeaver', c: 'ides', dn: 'DBeaver', s: 'DBeaver Community Edition database GUI. Requires a desktop variant.', t: ['dbeaver', 'database', 'sql', 'gui', 'ide'],
      needs: 'desktop', params: [P('DBEAVER_VERSION', 'latest', ['latest', '25.3.5'])],
      exts: ['connections-shared', 'drivers-shared', 'scripts-shared'] },

    // ── languages ───────────────────────────────────────────────────────────
    { n: 'go', c: 'languages', dn: 'Go', p: 1, s: 'Go toolchain with gopls LSP and Delve debugger', t: ['go', 'golang', 'backend'],
      params: [P('GO_VERSION', '1.25.7', ['1.25.7', '1.25.0', '1.24.13', '1.24.0', '1.23.12'])],
      exts: ['go-mod', 'go-pkg', 'kernel', 'linter', 'vscode-ext'] },
    { n: 'python', c: 'languages', dn: 'Python', p: 1, s: 'Python with pip package manager and venv support', t: ['python', 'data', 'scripting'],
      params: [P('PYTHON_VERSION', '3.13.12', ['3.14.2', '3.13.12', '3.13', '3.12.12', '3.11.14'])],
      exts: ['conda', 'conda-pkg', 'kernel', 'pip', 'pip-config', 'pip-pkg', 'repl-history', 'uv', 'uv-pkg', 'vscode-ext'] },
    { n: 'nodejs', c: 'languages', dn: 'Node.js', p: 1, s: 'Node.js runtime with npm package manager', t: ['nodejs', 'javascript', 'backend'],
      params: [P('NODE_VERSION', '22', ['22', '20', '18'])],
      exts: ['kernel', 'npm-install', 'npm-pkg', 'npm-upgrade', 'npmrc', 'pnpm-install', 'repl-history', 'vscode-ext', 'yarn-install', 'yarn-pkg'] },
    { n: 'java', c: 'languages', dn: 'Java', p: 1, s: 'Java JDK with configurable version and distribution', t: ['java', 'jvm', 'backend'],
      params: [P('JDK_VERSION', '25', ['25', '21', '17', '11', '8']), P('JDK_VENDOR', 'temurin', ['temurin', 'corretto', 'openjdk'])],
      exts: ['gradle', 'gradle-deps', 'jbang', 'jenv', 'kernel', 'kernel-jjava', 'm2', 'maven', 'mvn-install', 'vscode-ext'] },
    { n: 'rust', c: 'languages', dn: 'Rust', p: 1, s: 'Rust toolchain with Cargo and rustup', t: ['rust', 'systems', 'compiled'],
      params: [P('RUST_VERSION', 'stable', ['stable', 'nightly', '1.84.0', '1.83.0'])],
      exts: ['cargo-build', 'cargo-cache', 'cargo-pkg', 'credential', 'kernel', 'vscode-ext'] },
    { n: 'kotlin', c: 'languages', dn: 'Kotlin', s: 'Kotlin language for JVM development (requires java)', t: ['kotlin', 'jvm'], req: ['java'],
      params: [P('KOTLIN_VERSION', 'latest', ['latest', '2.0.20', '2.0.0', '1.9.24'])], exts: ['kernel', 'vscode-ext'] },
    { n: 'ruby', c: 'languages', dn: 'Ruby', t: ['ruby'], exts: ['bundle-install', 'credential', 'gem-pkg', 'kernel', 'repl-history', 'vscode-ext'] },
    { n: 'php', c: 'languages', dn: 'PHP', t: ['php'], exts: ['composer-install', 'pecl-pkg', 'repl-history', 'vscode-ext'] },
    { n: 'elixir', c: 'languages', dn: 'Elixir', t: ['elixir', 'beam'], exts: ['hex-pkg', 'mix-deps', 'repl-history', 'vscode-ext'] },
    { n: 'erlang', c: 'languages', dn: 'Erlang', t: ['beam'], exts: ['vscode-ext'] },
    { n: 'clojure', c: 'languages', dn: 'Clojure', t: ['jvm'], exts: ['vscode-ext'] },
    { n: 'scala', c: 'languages', dn: 'Scala', t: ['jvm'], exts: ['vscode-ext'] },
    { n: 'haskell', c: 'languages', dn: 'Haskell', t: ['functional'], exts: ['cabal-pkg', 'kernel', 'vscode-ext'] },
    { n: 'bun', c: 'languages', dn: 'Bun', t: ['javascript'], exts: ['bun-install', 'bun-pkg', 'vscode-ext'] },
    { n: 'deno', c: 'languages', dn: 'Deno', t: ['javascript'], exts: ['pkg', 'tool', 'vscode-ext'] },
    { n: 'csharp', c: 'languages', dn: 'C#', t: ['dotnet'], exts: ['dotnet-pkg', 'vscode-ext', 'wasm-tools'] },
    { n: 'dotnet', c: 'languages', dn: '.NET', t: ['dotnet'], exts: ['dotnet-pkg'] },
    { n: 'fsharp', c: 'languages', dn: 'F#', t: ['dotnet', 'functional'], exts: ['vscode-ext'] },
    { n: 'clang', c: 'languages', dn: 'Clang (C/C++)', t: ['c', 'compiled'], exts: ['kernel', 'vscode-ext'] },
    { n: 'gcc', c: 'languages', dn: 'GCC (C/C++)', t: ['c', 'compiled'], exts: ['vscode-ext'] },
    { n: 'flutter', c: 'languages', dn: 'Flutter', t: ['mobile'], exts: ['android', 'linux-desktop', 'vscode-ext'] },
    { n: 'swift', c: 'languages', dn: 'Swift', t: ['compiled'], exts: ['vscode-ext'] },
    { n: 'zig', c: 'languages', dn: 'Zig', t: ['compiled'], exts: ['vscode-ext'] },
    { n: 'nim', c: 'languages', dn: 'Nim', t: ['compiled'], exts: ['vscode-ext'] },
    { n: 'crystal', c: 'languages', dn: 'Crystal', t: ['compiled'], exts: ['vscode-ext'] },
    { n: 'lua', c: 'languages', dn: 'Lua', t: ['scripting'], exts: ['luarocks-pkg', 'vscode-ext'] },
    { n: 'julia', c: 'languages', dn: 'Julia', t: ['data'], exts: ['vscode-ext'] },
    { n: 'r', c: 'languages', dn: 'R', t: ['data'], exts: ['kernel', 'vscode-ext'] },
    { n: 'octave', c: 'languages', dn: 'GNU Octave', t: ['math'], exts: ['kernel', 'vscode-ext'] },
    { n: 'elm', c: 'languages', dn: 'Elm', t: ['functional', 'web'], exts: ['vscode-ext'] },
    { n: 'rescript', c: 'languages', dn: 'ReScript', t: ['web'], exts: ['vscode-ext'] },
    { n: 'roc', c: 'languages', dn: 'Roc', t: ['functional'], exts: ['vscode-ext'] },
    { n: 'fpc', c: 'languages', dn: 'Free Pascal', t: ['compiled'], exts: ['vscode-ext'] },

    // ── tools ───────────────────────────────────────────────────────────────
    { n: 'notebook', c: 'tools', dn: 'Jupyter Notebook', s: 'JupyterLab notebook server (requires python)', t: ['jupyter', 'notebook', 'python'],
      req: ['python'], params: [P('NOTEBOOK_PORT', '18888', ['18888', '8888'])], exts: ['autostart', 'expose', 'lab-settings-shared'] },
    { n: 'playwright', c: 'tools', dn: 'Playwright', s: 'Playwright browser automation and end-to-end testing framework', t: ['playwright', 'testing', 'e2e', 'browser', 'automation'],
      req: ['nodejs'], params: [P('PLAYWRIGHT_BROWSERS', 'chromium', ['chromium', 'chromium,firefox', 'chromium,firefox,webkit', 'all']), P('PLAYWRIGHT_VERSION', 'latest', ['latest', '1.58.2'])],
      exts: ['dotnet', 'java', 'python', 'vscode-ext'] },
    { n: 'apt-pkg', c: 'tools', dn: 'apt Packages', s: 'Install Debian/Ubuntu system packages via apt', t: ['apt', 'system', 'packages'],
      params: [L('APT_PKGS', 'plain name, or pkg=version for a full Debian version string \u2014 htop=3.0.5-7', 'add a package, Enter to commit')], exts: [] },
    { n: 'brew-pkg', c: 'tools', dn: 'brew Packages', s: 'Install packages via Homebrew', t: ['homebrew', 'brew', 'packages'], req: ['homebrew'],
      params: [L('BREW_PKGS', 'plain name is the normal form; only Homebrew\u2019s own versioned formulae pin \u2014 node@20', 'add a formula, Enter to commit')], exts: [] },
    { n: 'homebrew', c: 'tools', dn: 'Homebrew', t: ['packages'], exts: [] },
    { n: 'cloudbeaver', c: 'tools', dn: 'CloudBeaver', s: 'Web-based SQL database management GUI', t: ['cloudbeaver', 'database', 'sql', 'gui', 'dbeaver'],
      params: [P('CLOUDBEAVER_VERSION', '25.3.5', ['25.3.5', '25.3', 'latest']), P('CLOUDBEAVER_PORT', '8978', ['8978', '18978'])], exts: ['autostart', 'expose'] },
    { n: 'dind', c: 'tools', dn: 'Docker-in-Docker', s: 'Docker-in-Docker support for container workflows', t: ['docker', 'dind'], dind: 1, exts: ['docker-config'] },
    { n: 'gh', c: 'tools', dn: 'GitHub CLI', s: 'GitHub CLI for repository and PR management', t: ['github', 'cli', 'git'],
      params: [P('GH_VERSION', 'latest', ['latest', '2.97.0', '2.96.0'])], exts: ['copilot', 'credential'] },
    { n: 'openssh', c: 'tools', dn: 'OpenSSH Client', t: ['network'], exts: ['credential', 'expose', 'server'] },
    { n: 'nginx', c: 'tools', dn: 'nginx', t: ['server', 'web'], exts: ['expose'] },
    { n: 'apache', c: 'tools', dn: 'Apache HTTP Server', t: ['server', 'web'], exts: ['expose'] },
    { n: 'android-sdk', c: 'tools', dn: 'Android SDK', t: ['mobile'], exts: ['avd-cache', 'emulator', 'kvm'] },
    { n: 'excalidraw', c: 'tools', dn: 'Excalidraw', t: ['diagram'], exts: ['autostart', 'expose'] },
    { n: 'mermaid', c: 'tools', dn: 'Mermaid', t: ['diagram'], exts: ['autostart', 'expose'] },
    { n: 'plantuml', c: 'tools', dn: 'PlantUML', t: ['diagram'], exts: ['autostart', 'expose'] },
    { n: 'graphviz', c: 'tools', dn: 'Graphviz', t: ['diagram'], exts: [] },
    { n: 'neovim', c: 'tools', dn: 'Neovim', t: ['editor'], exts: ['config', 'config-shared', 'data-cache'] },
    { n: 'zsh', c: 'tools', dn: 'Zsh', t: ['shell'], exts: ['default', 'starship-shared'] },
    { n: 'shell-history', c: 'tools', dn: 'Shell History', t: ['shell'], exts: [] },
    { n: 'fzf', c: 'tools', dn: 'fzf', t: ['shell'], exts: [] },
    { n: 'direnv', c: 'tools', dn: 'direnv', t: ['shell'], exts: [] },
    { n: 'no-sudo', c: 'tools', dn: 'No sudo', t: ['security'], exts: [] },
    { n: 'git-credential', c: 'tools', dn: 'Git Credentials', t: ['git'], exts: [] },
    { n: 'lazygit', c: 'tools', dn: 'lazygit', t: ['git'], exts: [] },
    { n: 'lazydocker', c: 'tools', dn: 'lazydocker', t: ['docker'], exts: [] },
    { n: 'dive', c: 'tools', dn: 'dive', t: ['docker'], exts: [] },
    { n: 'docker-buildx', c: 'tools', dn: 'Docker Buildx', t: ['docker'], exts: [] },
    { n: 'docker-compose', c: 'tools', dn: 'Docker Compose', t: ['docker'], exts: [] },
    { n: 'kubectl', c: 'tools', dn: 'kubectl', t: ['kubernetes'], exts: ['credential'] },
    { n: 'kubectx', c: 'tools', dn: 'kubectx', t: ['kubernetes'], exts: [] },
    { n: 'kustomize', c: 'tools', dn: 'Kustomize', t: ['kubernetes'], exts: [] },
    { n: 'helm', c: 'tools', dn: 'Helm', t: ['kubernetes'], exts: [] },
    { n: 'k9s', c: 'tools', dn: 'k9s', t: ['kubernetes'], exts: [] },
    { n: 'k3d', c: 'tools', dn: 'k3d', t: ['kubernetes'], exts: [] },
    { n: 'kind', c: 'tools', dn: 'kind', t: ['kubernetes'], exts: [] },
    { n: 'stern', c: 'tools', dn: 'stern', t: ['kubernetes'], exts: [] },
    { n: 'terraform', c: 'tools', dn: 'Terraform', t: ['infra'], exts: [] },
    { n: 'pulumi', c: 'tools', dn: 'Pulumi', t: ['infra'], exts: [] },
    { n: 'ansible', c: 'tools', dn: 'Ansible', t: ['infra'], exts: [] },
    { n: 'aws-cli', c: 'tools', dn: 'AWS CLI', t: ['cloud'], exts: ['credential'] },
    { n: 'aws-cdk', c: 'tools', dn: 'AWS CDK', t: ['cloud'], exts: [] },
    { n: 'aws-sam-cli', c: 'tools', dn: 'AWS SAM CLI', t: ['cloud'], exts: ['credential', 'dind'] },
    { n: 'azure-cli', c: 'tools', dn: 'Azure CLI', t: ['cloud'], exts: ['credential'] },
    { n: 'gcloud', c: 'tools', dn: 'Google Cloud SDK', t: ['cloud'], exts: ['credential'] },
    { n: 'firebase', c: 'tools', dn: 'Firebase CLI', t: ['cloud'], exts: ['credential'] },
    { n: 'act', c: 'tools', dn: 'act', t: ['ci'], exts: [] },
    { n: 'just', c: 'tools', dn: 'just', t: ['build'], exts: [] },
    { n: 'make', c: 'tools', dn: 'GNU Make', t: ['build'], exts: [] },
    { n: 'cmake', c: 'tools', dn: 'CMake', t: ['build'], exts: [] },
    { n: 'conan', c: 'tools', dn: 'Conan', t: ['build', 'c'], exts: ['conan-pkg'] },
    { n: 'build-essential', c: 'tools', dn: 'Build Essentials', t: ['build'], exts: [] },
    { n: 'gradle', c: 'tools', dn: 'Gradle', t: ['build', 'jvm'], exts: [] },
    { n: 'sbt', c: 'tools', dn: 'sbt', t: ['build', 'jvm'], exts: [] },
    { n: 'protobuf', c: 'tools', dn: 'Protocol Buffers', t: ['rpc'], exts: ['go'] },
    { n: 'buf', c: 'tools', dn: 'buf', t: ['rpc'], exts: [] },
    { n: 'conda', c: 'tools', dn: 'Conda', t: ['python', 'packages'], exts: [] },
    { n: 'duckdb', c: 'tools', dn: 'DuckDB', t: ['database', 'data'], exts: [] },
    { n: 'cypress', c: 'tools', dn: 'Cypress', t: ['testing', 'e2e'], exts: [] },
    { n: 'puppeteer', c: 'tools', dn: 'Puppeteer', t: ['testing', 'browser'], exts: [] },
    { n: 'selenium', c: 'tools', dn: 'Selenium', t: ['testing', 'browser'], exts: [] },
    { n: 'ffmpeg', c: 'tools', dn: 'FFmpeg', t: ['media'], exts: [] },
    { n: 'remotion', c: 'tools', dn: 'Remotion', t: ['media'], exts: [] },
    { n: 'vhs', c: 'tools', dn: 'VHS (terminal recorder)', t: ['media'], exts: [] },
    { n: 'obsidian', c: 'tools', dn: 'Obsidian', t: ['notes', 'gui'], needs: 'desktop', exts: [] },
    { n: 'freeplane', c: 'tools', dn: 'Freeplane', t: ['notes', 'gui'], needs: 'desktop', exts: [] },
    { n: 'mkcert', c: 'tools', dn: 'mkcert', t: ['network'], exts: [] },
    { n: 'ssh', c: 'tools', dn: 'SSH Config', t: ['network'], exts: [] },
    { n: 'bash-nb-kernel', c: 'tools', dn: 'Bash Notebook Kernel', t: ['notebook', 'kernel'], req: ['notebook'], exts: [] }
  ];

  T.forEach(function (t) {
    t.s = t.s || '';
    t.t = t.t || [];
    t.req = t.req || [];
    t.exts = (t.exts || []).map(function (e) {
      var f = famOf(e), ext = { n: e, s: f.s, a: f.a || 0, needs: f.needs, req: (f.req || []).slice() };
      if (f.list) ext.list = { k: e.replace(/-/g, '_').toUpperCase(), hint: 'one requirement per entry \u2014 a version pin uses this manager\u2019s own syntax', ph: 'add an entry, Enter to commit' };
      if (e === 'expose') {
        if (FIXED[t.n]) { ext.params = [{ k: FIXED[t.n][0], d: FIXED[t.n][1], sug: [FIXED[t.n][1], '1' + FIXED[t.n][1], '+OFFSET'] }]; ext.container = FIXED[t.n][1]; }
        else if (FOLLOWS[t.n]) ext.follow = { k: t.n.toUpperCase().replace(/-/g, '_') + '_HOST_PORT', from: FOLLOWS[t.n] };
        ext.s = FIXED[t.n]
          ? 'Publish it to the host. The setup script hardcodes container port ' + FIXED[t.n][1] + ', so this param is the HOST port.'
          : 'Publish it to the host. The host port defaults to a reference to the service port, so moving the service moves the mapping.';
      }
      return ext;
    });
    t.params = (t.params || []).map(function (p) { return p; });
  });

  window.BOOTH_CATALOG = {
    templates: T,
    cats: [
      { id: 'languages', label: 'Languages' }, { id: 'databases', label: 'Databases' },
      { id: 'tools', label: 'Tools' }, { id: 'ai-tools', label: 'AI Tools' },
      { id: 'ides', label: 'IDEs' }, { id: 'desktops', label: 'Desktops' },
      { id: 'browsers', label: 'Browsers' }, { id: 'education', label: 'Education' }
    ],
    variants: [
      { id: 'base', label: 'base', kind: 'terminal', meaning: 'A shell in the container. No editor, no display \u2014 reach it with booth shell.' },
      { id: 'notebook', label: 'notebook', kind: 'notebook', meaning: 'JupyterLab is the primary service, fronted by the booth\u2019s nginx on the booth port. Kernels have a home; editor extensions do not.' },
      { id: 'codeserver', label: 'codeserver', kind: 'editor', meaning: 'code-server is the primary service on the booth port. Editor extension ids have a home; desktop apps do not.' },
      { id: 'desktop-xfce', label: 'desktop-xfce', kind: 'desktop', meaning: 'XFCE over VNC/noVNC. Desktop VS Code is baked in, so editor extensions and desktop IDEs both have a home.' },
      { id: 'desktop-kde', label: 'desktop-kde', kind: 'desktop', meaning: 'KDE Plasma over VNC/noVNC, with desktop VS Code baked in.' },
      { id: 'desktop-lxqt', label: 'desktop-lxqt', kind: 'desktop', meaning: 'LXQt over VNC/noVNC, with desktop VS Code baked in.' },
      { id: 'desktop-wayland', label: 'desktop-wayland', kind: 'desktop', meaning: 'Wayland session, with desktop VS Code baked in.' },
      { id: 'terminal', label: 'terminal', kind: 'terminal', meaning: 'A host terminal session against the container \u2014 nothing is published.' }
    ],
    local: []
  };
})();
