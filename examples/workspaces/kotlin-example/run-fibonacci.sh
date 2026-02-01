#!/bin/bash
# Run Fibonacci generator
cd "$(dirname "$0")"
kotlinc src/Fibonacci.kt -include-runtime -d fibonacci.jar 2>/dev/null
java -jar fibonacci.jar "$@"
