# Treemoji (Go Example)

A tiny, deterministic `tree`-like CLI with emojis — written in Go.

**Stack:** Go, gopls, delve

## Quick start

```bash
# 1. Launch the booth
cd examples/go-example
../../codingbooth

# 2. Inside the booth — build the project
./build.sh

# 3. Run it
./run-treemoji.sh
# or directly:
./bin/treemoji-linux-amd64

# 4. Run the tests
./run-go-test.sh
# or:
go test ./...
```

## Features

- Deterministic, stable output (case-insensitive sorted)
- Optional emoji prefixes for directories/files/symlinks
- Filter hidden entries (default) or include them with `-a`
- Directories-only mode with `-d`
- Limit traversal depth with `-L N`

## Build from source

Requires Go 1.21+.

```bash
./build.sh
# Or directly with Go tools:
go build -o bin/treemoji ./cmd/treemoji
```

## Usage

```text
Treemoji — a tiny tree-like CLI with emojis
Usage: treemoji [options] [directory]

Options:
  -a            All files, include hidden (like tree -a)
  -d            List directories only
  -L int        Max display depth of the directory tree (0 = unlimited)
  -no-emoji     Disable emojis in output
  -version      Print version and exit
```

- If no `directory` is provided, Treemoji uses the current working directory.
- If a file path is provided instead of a directory, Treemoji prints a single line for that file.

## Examples

Print the current folder tree with emojis (default):

```bash
treemoji
```

Include hidden files and folders:

```bash
treemoji -a
```

List directories only, up to depth 2:

```bash
treemoji -d -L 2
```

Disable emojis:

```bash
treemoji --no-emoji
```

Show version and exit:

```bash
treemoji --version
```

### Sample output

```text
my-project
├── bin
│   └── treemoji
├── build.sh
├── cmd
│   └── treemoji
│       └── main.go
├── internal
│   └── tree
│       ├── tree.go
│       └── tree_test.go
├── run.sh
├── test.sh
├── go.mod
└── README.md
```

With emojis (default):

```text
my-project
├── 📁 bin
│   └── 📄 treemoji
├── 📄 build.sh
├── 📁 cmd
│   └── 📁 treemoji
│       └── 📄 main.go
├── 📁 internal
│   └── 📁 tree
│       ├── 📄 tree.go
│       └── 📄 tree_test.go
├── 📄 run.sh
├── 📄 test.sh
├── 📄 go.mod
└── 📄 README.md
```

Note: Emojis are chosen by entry type: `📁` for directories, `📄` for regular files, and `🔗` for symlinks.

## Development

Run locally:

```bash
./run.sh                        # runs treemoji on the project root
```

Run tests:

```bash
./test.sh
# or
go test ./...
```

Linting/formatting: follow standard Go formatting; this repo uses idiomatic Go style.

## How it works (high level)
- Entry traversal uses `os.ReadDir` with filtering for hidden names (unless `-a`) and directories-only mode (`-d`).
- Stable output is ensured by sorting entries case-insensitively.
- Tree drawing uses `│`, `├──`, and `└──` with a prefix stack, similar to classic `tree`.
- Emoji selection is based on the entry type (directory, file, symlink) and can be disabled with `-no-emoji`.

## Versioning
Current version: `v0.1.0`.

## License
Specify your license here (e.g., MIT). If adding a license file, update this section accordingly.

## Acknowledgements
Inspired by the classic Unix `tree` command — with a sprinkle of emojis for fun.
