#!/bin/bash
# Run tests
cd "$(dirname "$0")"
ruby test/wordcount_test.rb
