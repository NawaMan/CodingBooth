# Elixir Example

This example is a minimal Elixir program running on the BEAM VM. The bundled palindrome checker normalizes the text you pass — dropping case, spaces, and punctuation — and reports whether it reads the same forwards and backwards. This example earns its spot on version compatibility: Elixir runs on the Erlang BEAM VM, and every Elixir release only supports a specific window of OTP versions. Pair the wrong two by hand and you get cryptic BEAM load errors or a build that mysteriously refuses to compile — a classic time sink for anyone new to the ecosystem. Here Elixir comes with a known-compatible Erlang/OTP already bundled, so the language and its runtime agree from the start, and you can still pin a different Elixir with the `ELIXIR_VERSION` build arg and get a matching OTP along with it.

**Stack:** Elixir 1.18.4, Erlang/OTP 25

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
| Runtime         | Erlang/OTP 25                        |
| VS Code support | ElixirLS extension                   |
| Sample          | `lib/palindrome.ex`                  |

Change the versions with `booth config`, e.g.
`booth config --no-tui --overwrite --remove-select elixir --add-select 'elixir:1.19.5+vscode-ext+repl-history'`.

### Why OTP 25 and Elixir 1.18.4

The booth selects `erlang:25` and `elixir:1.18.4` rather than the templates' defaults (OTP 28,
latest Elixir). OTP 28 comes from `ppa:rabbitmq/rabbitmq-erlang-28`, which only publishes arm64
builds of a few metapackages — not the `erlang-base`/`erlang-dev`/… packages the erlang setup
installs by name — so on arm64 apt silently falls back to Ubuntu's OTP 25 anyway. Elixir 1.19
dropped OTP 25, so that mismatch 404s fetching `elixir-otp-25.zip`. Elixir 1.18.4 still ships an
OTP 25 build, so this pair installs identically on amd64 and arm64.
