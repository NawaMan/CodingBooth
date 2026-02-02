#!/bin/bash
# Run the word counter
cd "$(dirname "$0")"
ruby src/wordcount.rb "$@"
