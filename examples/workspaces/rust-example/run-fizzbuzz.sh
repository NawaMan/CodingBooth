#!/bin/bash
# Run FizzBuzz
cd "$(dirname "$0")"
cargo run -- "${@:-1 15}"
