# Phase 5: CLI Commands

## Tasks

22. Implement `./booth design --list` — list all templates by category
23. Implement `./booth design --search <term>` — prefix match on name, display-name, tags
24. Implement `./booth design --select <names> --non-interactive` — select by name, generate with defaults
25. Implement `--param <name.param=value>` — override setup params
26. Implement `--variant`, `--port` CLI flags
27. Implement `--dryrun` — print what would be generated
28. Implement `--templates-path` — load templates from local directory
29. Wire `design` subcommand into `coding-booth` main and `booth` wrapper
30. Tests for CLI commands

## Suggested Package Structure

```
internal/
└── design/
    └── cli/
        ├── list.go           # --list command
        ├── search.go         # --search command
        └── select.go         # --select --non-interactive command
```

The CLI interface serves both as a testing interface for backend logic and as a scriptable alternative to the interactive modes.

## --list

```bash
./booth design --list
```

Output:
```
Languages
  python          Python                     [python, scripting]
  go              Go                         [golang, backend]
  java            Java                       [java, jvm]
  nodejs          Node.js                    [node, javascript]
  rust            Rust                       [rust, systems]

Frameworks
  spring          Spring Boot                [java, web, backend]
  django          Django                     [python, web, backend]

Tools
  claude-code     Claude Code                [ai, assistant, anthropic]
  neovim          Neovim                     [editor, vim]

Credentials
  ssh             SSH Keys                   [git, authentication]
  claude          Claude Code Credentials    [ai, anthropic]
```

## --search

```bash
./booth design --search "go"
```

Output:
```
Languages
  go              Go                         [golang, backend]

Frameworks
  golang-migrate  Golang Migrate             [go, database, migration]
```

**Match behavior:** Prefix match on any word in name, display-name, or tags.

## --select

```bash
# Basic selection with defaults
./booth design --select go,claude-code --variant codeserver --non-interactive

# With param overrides (format: template.setup.param=value)
./booth design --select go,java \
  --param "go.go--setup.version=1.24" \
  --param "java.jdk--setup.version=21" \
  --param "java.jdk--setup.vendor=corretto" \
  --variant desktop-xfce --non-interactive

# Dry run to preview
./booth design --select python,django --variant codeserver --dryrun

# Force overwrite existing .booth/
./booth design --select nodejs --variant codeserver --non-interactive
```

**Param format:** `template.setup.param=value`
**Implementation note:** Do not implement the `template.param=value` shorthand for now.

## CLI Flags Reference

| Flag                         | Description                                                                         |
|------------------------------|-------------------------------------------------------------------------------------|
| `--list`                     | List all templates by category                                                      |
| `--search <term>`            | Search templates (prefix match of name, display-name and tag)                       |
| `--select <names>`           | Comma-separated template names to select – the name must fully match. Error if not. |
| `--param <name.param=value>` | Override a template's setup param                                                   |
| `--variant <name>`           | Set variant (codeserver, notebook, desktop-xfce, etc.)                              |
| `--port <value>`             | Set port (number, NEXT, RANDOM)                                                     |
| `--non-interactive`          | Generate files immediately (no interactive mode)                                    |
| `--dryrun`                   | Print what would be generated without writing files                                 |
| `--templates-path <path>`    | Override templates location (for development)                                       |
| `--advance`                  | Enter Advanced mode TUI                                                             |

## Verbose Logging

When `--verbose` is passed, print detailed logging throughout the design flow (template loading, selection resolution, file generation).
