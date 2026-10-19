#!/bin/bash
# API Latency Report: p50/p95/p99 and error rate per endpoint
cd "$(dirname "$0")"
python src/latency.py "$@"
