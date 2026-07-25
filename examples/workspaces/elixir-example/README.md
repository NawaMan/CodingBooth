# Elixir Example

This example is a minimal Elixir program running on the BEAM VM. The bundled palindrome checker normalizes the text you pass — dropping case, spaces, and punctuation — and reports whether it reads the same forwards and backwards. This example earns its spot on version compatibility: Elixir runs on the Erlang BEAM VM, and every Elixir release only supports a specific window of OTP versions. Pair the wrong two by hand and you get cryptic BEAM load errors or a build that mysteriously refuses to compile — a classic time sink for anyone new to the ecosystem. Here Elixir comes with a known-compatible Erlang/OTP already bundled, so the language and its runtime agree from the start, and you can still pin a different Elixir with the `ELIXIR_VERSION` build arg and get a matching OTP along with it.

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
