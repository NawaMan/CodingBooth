---
name: test-add-unit
description: Add a Go unit test under cli/src/ — pure logic, no container, no shell harness. Use for anything decidable from inputs and outputs: parsing, resolution, path and arg assembly, precedence rules. Always the first choice when the behaviour is reachable in Go; the shell suites exist for what Go cannot see.
---

# Add a Go unit test

`$ARGUMENTS` is the behaviour to cover. Go tests live beside the code in `cli/src/`, run in
milliseconds, and need no image.

**Reach for this first.** If the behaviour is decidable from inputs and outputs, it belongs here
rather than in a shell suite. A rule of thumb: when you catch yourself about to start a container to
check a string, the logic that built the string wants a unit test, and often wants extracting into a
pure function so it can have one.

`tests/unit/run-all-go-tests.sh` just delegates to `go test` — there is nothing to register.

## 1. Name and place it

Beside the code, following `docs/CODESTYLE.md`:

- `list.go` → `list_test.go`, one type per file, `snake_case` filenames
- `api_test.go` for API-level tests, `example_test.go` for documentation examples

## 2. House style — read `docs/CODESTYLE.md`

This repo deliberately departs from Go convention on naming, and a test that follows stock Go style
will look wrong here:

- **No single-letter variables.** `index`/`value`, not `i`/`v`. `fn`, not `f`. Receivers are
  `thisList`, not `l`.
- **Generic type parameters are `TYPE`**, not `T`.
- **Comments document surprises**, not the obvious. Explain *why* when the decision isn't evident;
  skip restating what the signature already says.

## 3. Table tests, with names that read as claims

The prevailing pattern, and the `name` field is the failure message someone reads:

```go
tests := []struct {
	name string
	ctx  appctx.AppContext
	want bool
}{
	{"a booth serving a UI opens", browserTestContext(true, false, false, 10000), true},
	{"--no-browser stays shut", browserTestContext(false, false, false, 10000), false},
	{"a booth given a command has no page", browserTestContext(true, false, false, 10000, "bash"), false},
}

for _, tt := range tests {
	t.Run(tt.name, func(t *testing.T) {
		if got := shouldOpenBrowser(tt.ctx); got != tt.want {
			t.Errorf("shouldOpenBrowser() = %v, want %v", got, tt.want)
		}
	})
}
```

Write the name as a claim about behaviour — "a booth given a command has no page" — not a
restatement of the inputs.

## 4. Cover what matters, per CODESTYLE

**Keep:** deep-copy and aliasing checks, core invariants, edge cases that could actually fail,
real-world workflows. **Skip:** obvious behaviour already covered by other tests, redundant
variations, several tests of one concept.

When a test exists because of a *bug*, say so in a comment above it — what went wrong and what the
test would catch. A named regression outlives whoever fixed it.

## 5. Make host-dependent logic testable

Where behaviour depends on the host — OS, environment, filesystem — extract the decision into a pure
function taking those as parameters, so it is testable from any machine. `headlessReason(goos, wsl,
display, waylandDisplay)` exists for exactly that: the Linux-over-SSH case it guards is the one
least likely to be reproducible on the machine running the tests.

## 6. Run it

```bash
(cd cli && go test ./src/pkg/<package>/ -count=1 -run TestYourThing)
(cd cli && go test ./src/pkg/<package>/ -count=1)
(cd cli && go test ./...)
(cd cli/src && gofmt -l ./pkg/<package>/ && go vet ./pkg/<package>/)
```

`-count=1` defeats the test cache. `gofmt -l` prints nothing when formatting is clean — note that a
couple of pre-existing files in this repo are unformatted, so check that it names *your* file before
reformatting anything.
