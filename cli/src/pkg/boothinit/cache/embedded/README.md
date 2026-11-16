# Embedded template catalog

`templates.zip` here is generated, not committed: `build/cli-build.sh` writes it with
`go run ./src/cmd/templates-pack` before `go build`. It is the repository's `templates/`
tree, with the build's version as the zip comment. `booth config` and `booth template`
read it for that version, so they need no download.

A binary built without it (a plain `go build`) still works: it uses the cached
`templates.zip` for the version, or downloads it from the GitHub release.
See docs/implementations/BOOTHINIT.md.
