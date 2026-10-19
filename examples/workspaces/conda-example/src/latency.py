#!/usr/bin/env python3
"""
API Latency Report - p50 / p95 / p99 and error rate per endpoint

Reads a request log (data/requests.csv) with pandas, installed via conda.
The notebook Latency.ipynb charts the same log.
"""

import sys
from pathlib import Path

import pandas as pd

LOG = Path(__file__).resolve().parent.parent / "data" / "requests.csv"


def load(path: Path = LOG) -> pd.DataFrame:
    """The request log, one row per request, with an `is_error` column (5xx)."""
    log = pd.read_csv(path, parse_dates=["timestamp"])
    log["route"] = log["method"] + " " + log["endpoint"]
    log["is_error"] = log["status"] >= 500
    return log


def report(log: pd.DataFrame) -> pd.DataFrame:
    """Per route: request count, latency percentiles (ms) and error rate (%)."""
    by_route = log.groupby("route")
    table = pd.DataFrame({
        "requests": by_route.size(),
        "p50_ms":   by_route["duration_ms"].quantile(0.50),
        "p95_ms":   by_route["duration_ms"].quantile(0.95),
        "p99_ms":   by_route["duration_ms"].quantile(0.99),
        "errors_%": by_route["is_error"].mean() * 100,
    })
    return table.sort_values("p95_ms", ascending=False)


def show_help():
    print("API Latency Report (using pandas)")
    print("")
    print("p50/p95/p99 latency and 5xx error rate per endpoint, from data/requests.csv.")
    print("")
    print("Usage: latency.py [endpoint-filter]")
    print("")
    print("Examples:")
    print("  latency.py                 # every endpoint, slowest p95 first")
    print("  latency.py /api/orders     # only routes whose path contains /api/orders")


def main():
    args = sys.argv[1:]
    if args and args[0] in ("-h", "--help"):
        show_help()
        return

    log = load()
    if args:
        log = log[log["endpoint"].str.contains(args[0], regex=False)]
        if log.empty:
            print(f"Error: no requests match {args[0]!r}", file=sys.stderr)
            sys.exit(1)

    table = report(log)
    first, last = log["timestamp"].min(), log["timestamp"].max()
    print(f"{len(log)} requests, {first:%H:%M:%S} to {last:%H:%M:%S}\n")
    print(table.to_string(float_format=lambda v: f"{v:.1f}"))

    slowest = table.index[0]
    print(f"\nSlowest p95: {slowest} ({table.loc[slowest, 'p95_ms']:.0f} ms)")


if __name__ == "__main__":
    main()
