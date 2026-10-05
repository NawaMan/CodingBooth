# Gleam Example

This example is a small web service written in [Gleam](https://gleam.run), a type-safe functional language that compiles to Erlang and runs on the BEAM. It uses [Wisp](https://hexdocs.pm/wisp/) for routing on the [Mist](https://hexdocs.pm/mist/) HTTP server, with an HTML home page, a JSON greeting, a POST endpoint that reverses text, and a Roman numeral converter (`/roman/2026` → `MMXXVI`, `/roman/XIV` → `14`). A second Gleam program in the same project, a command-line client, sends its input to that converter and prints the answers. Gleam needs two things that have to agree with each other: the `gleam` compiler and an Erlang/OTP runtime to run the compiled code (plus `rebar3` for the Erlang code some packages contain). Here both come from the Boothfile, and the exact Hex package versions are locked in `manifest.toml`, so `gleam test` builds the same dependency tree on any machine.

**Stack:** Gleam 1.18.1, Erlang/OTP 28, Wisp 2 + Mist 6, code-server with the Gleam extension

## Quick start

```bash
# 1. Launch the booth (code-server opens in your browser)
cd examples/workspaces/gleam-example
booth

# 2. Inside the booth
just --list
just test          # gleam test: the router tested without a socket (wisp/simulate)
just start         # serve on :8000 in the background
curl localhost:8000/greet/booth             # {"greeting":"Hello, booth!"}
curl -X POST --data gleam localhost:8000/reverse   # maelg
just client                 # the CLI client, default input: 2026  →  MMXXVI
just client XIV 1999 4000   # several at once; 4000 is rejected (exit 1)
just stop

# 3. From the host: the port is published relative to the booth's own port
booth--expose list        # e.g. 8000 -> 0.0.0.0:18000 for a booth on port 10000
```

Port 8000 is published as `+8000:8000`: the host port is the **booth port + 8000**, so two booths
on different ports never collide. A booth on port 10000 serves the app at http://localhost:18000;
`booth--expose list` inside the booth shows the actual mapping. Use `booth --offset-base 0` if you
want it on host port 8000 exactly.

The first `just test` or `just start` downloads the Hex packages into `build/` and compiles them,
which takes a while. Later runs only recompile what changed.

## What's included

| Component       | Details                                                    |
|-----------------|------------------------------------------------------------|
| Language        | Gleam 1.18.1 (`gleam` compiler, build tool, formatter, LSP) |
| Runtime         | Erlang/OTP 28 + rebar3                                     |
| Web             | Wisp 2 on Mist 6, bound to `0.0.0.0:8000`, published as `+8000:8000` |
| VS Code support | `gleam.gleam` extension (uses the LSP built into `gleam`)  |
| Server sample   | `src/gleam_example/router.gleam`, `src/gleam_example/roman.gleam` |
| CLI sample      | `src/gleam_example/client.gleam` (gleam_httpc + JSON decoding) |

Change the versions with `booth config`, e.g.
`booth config --no-tui --overwrite --remove-select gleam --add-select 'gleam:1.17.0+vscode-ext'`.

## Layout

```
src/gleam_example.gleam          entry point: starts Mist on :8000
src/gleam_example/router.gleam   every route, pure request -> response
src/gleam_example/roman.gleam    Roman numerals both ways, standard spellings only
src/gleam_example/client.gleam   CLI: gleam run -m gleam_example/client -- <inputs>
test/gleam_example_test.gleam    unit, route (wisp/simulate) and client-formatting tests
gleam.toml / manifest.toml       dependencies / locked versions
start-server.sh / stop-server.sh what `just start` / `just stop` run
```

## The CLI client

`client.gleam` has its own `main`, so it is a separate program built from the same project:
`gleam run -m gleam_example/client -- <inputs>` (`just client` wraps it). Each input goes to
`GET /roman/<input>`. A number comes back as its numeral and a numeral as its number. With no
input it converts `2026`.

- `SERVER_URL` picks the server (default `http://localhost:8000`).
- Exit 0 when every input converts, 1 if the server rejected any (out of range, or not a standard
  numeral such as `IIII`), 2 if the server could not be reached.

## Tests

`.cb-tests/test001-wisp--on-host.sh` starts the booth, runs the in-booth suite (toolchain
versions, `just test`, the running server answering each route, and the CLI client's output and
exit codes, including with the server down), then checks the server is
reachable from the host at booth port + 8000 (the config's own `+8000:8000` mapping, not a
test-only `-p`) and gone after `just stop`.

```bash
examples/workspaces/run-example-tests.sh --example gleam-example
```
