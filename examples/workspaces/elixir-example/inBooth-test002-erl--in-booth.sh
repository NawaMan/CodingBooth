#!/bin/bash
echo "=== Testing erlang ==="
erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell
