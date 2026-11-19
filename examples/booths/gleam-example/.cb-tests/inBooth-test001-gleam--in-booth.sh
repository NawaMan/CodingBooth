#!/bin/bash
echo "=== Testing gleam + erlang ==="
gleam --version | grep -q "^gleam 1\.18\.1$" || { echo "expected gleam 1.18.1, got: $(gleam --version)"; exit 1; }
erl -noshell -eval 'io:format("OTP ~s~n",[erlang:system_info(otp_release)]), halt().'
