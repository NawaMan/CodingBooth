# Elixir Example

This example is a minimal Elixir program running on the BEAM VM. The bundled palindrome checker normalizes the text you pass — dropping case, spaces, and punctuation — and reports whether it reads the same forwards and backwards. This example earns its spot on version compatibility: Elixir runs on the Erlang BEAM VM, and every Elixir release only supports a specific window of OTP versions. Pair the wrong two by hand and you get cryptic BEAM load errors or a build that mysteriously refuses to compile — a classic time sink for anyone new to the ecosystem. Here Elixir comes with a known-compatible Erlang/OTP already bundled, so the language and its runtime agree from the start, and you can still pin a different Elixir with the `ELIXIR_VERSION` build arg and get a matching OTP along with it.

**Stack:** Elixir 1.18.4, Erlang/OTP 27

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/elixir-example
booth

# 2. Inside the booth — run the palindrome checker
just --list
just run racecar         # ./run-palindrome.sh "racecar"
```

## What's included

| Component       | Details                              |
|-----------------|--------------------------------------|
| Language        | Elixir 1.18.4                        |
| Runtime         | Erlang/OTP 27                        |
| VS Code support | ElixirLS extension                   |
| Sample          | `lib/palindrome.ex`                  |

Change the versions with `booth config`, e.g.
`booth config --no-tui --overwrite --remove-select elixir --add-select 'elixir:1.19.5+vscode-ext+repl-history'`.

### Why OTP 27 and Elixir 1.18.4

The booth pins `erlang:27` and `elixir:1.18.4` rather than the templates' defaults (OTP 28,
latest Elixir) to show a known-good pair held still. Each Elixir release ships prebuilt zips for
only some OTP majors: 1.18.4 has `elixir-otp-26.zip` and `elixir-otp-27.zip` but no OTP 28 build,
so `erlang:28` with `elixir:1.18.4` 404s fetching the Elixir zip. OTP comes from builds.hex.pm,
which publishes the same releases for amd64 and arm64, so this pair installs identically on both.
