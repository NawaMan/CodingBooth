# Elixir Example

A minimal Elixir program running on the BEAM VM.

**Stack:** Elixir 1.19, Erlang/OTP

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/elixir-example
booth

# 2. Inside the booth — run the palindrome checker
./run-palindrome.sh "racecar"
```

## What's included

| Component       | Details                              |
|-----------------|--------------------------------------|
| Language        | Elixir (default 1.19.5)              |
| Runtime         | Erlang/OTP (bundled with Elixir)     |
| VS Code support | ElixirLS extension                   |
| Sample          | `lib/palindrome.ex`                  |

Pin a different Elixir version with the `ELIXIR_VERSION` build arg in `.booth/Boothfile`.
