# Embedded prepare kit

`kit.tar.gz` here is generated, not committed: `build/cli-build.sh` writes it with
`go run ./src/cmd/prepare-kit` before `go build`, and `booth prepare` extracts it.
A binary built without it (a plain `go build`) still works; `booth prepare` then
needs `--source <checkout>`. See docs/REUSE_BOOTH.md.
