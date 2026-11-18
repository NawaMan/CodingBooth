module polyglot-go

go 1.23

// The community playwright-go binding. Its module path is the original author's
// (github.com/mxschmitt/playwright-go) even though the project now lives under the
// playwright-community org. run-polyglot.sh runs `go mod tidy` to fetch go.sum.
require github.com/mxschmitt/playwright-go v0.6100.0

require (
	github.com/deckarep/golang-set/v2 v2.8.0 // indirect
	github.com/go-jose/go-jose/v3 v3.0.5 // indirect
	github.com/go-stack/stack v1.8.1 // indirect
)
