#!/bin/bash
# Run Palindrome checker
cd "$(dirname "$0")"
elixir -r lib/palindrome.ex -e "Palindrome.CLI.main(System.argv())" -- "$@"
