#!/usr/bin/env python3
"""
Statistics Calculator - Compute basic statistics for a list of numbers

Demonstrates using NumPy (installed via conda) for statistical calculations.
"""

import sys
import numpy as np


def calculate_stats(numbers: list[float]) -> dict:
    """Calculate various statistics for a list of numbers."""
    arr = np.array(numbers)
    return {
        "count": len(arr),
        "sum": np.sum(arr),
        "mean": np.mean(arr),
        "median": np.median(arr),
        "std": np.std(arr),
        "min": np.min(arr),
        "max": np.max(arr),
        "range": np.ptp(arr),  # peak to peak (max - min)
    }


def format_stats(stats: dict) -> str:
    """Format statistics for display."""
    lines = [
        f"  Count:   {stats['count']}",
        f"  Sum:     {stats['sum']:.4g}",
        f"  Mean:    {stats['mean']:.4g}",
        f"  Median:  {stats['median']:.4g}",
        f"  Std Dev: {stats['std']:.4g}",
        f"  Min:     {stats['min']:.4g}",
        f"  Max:     {stats['max']:.4g}",
        f"  Range:   {stats['range']:.4g}",
    ]
    return "\n".join(lines)


def show_help():
    print("Statistics Calculator (using NumPy)")
    print("")
    print("Compute basic statistics for a list of numbers.")
    print("Uses NumPy for efficient numerical computations.")
    print("")
    print("Usage: stats.py <number> [number...]")
    print("")
    print("Examples:")
    print("  stats.py 1 2 3 4 5")
    print("  stats.py 10.5 20.3 15.7 18.2")
    print("  stats.py 100 200 150 175 180 190")


def main():
    args = sys.argv[1:]

    if not args:
        show_help()
        return

    try:
        numbers = [float(x) for x in args]
    except ValueError:
        print("Error: All arguments must be valid numbers")
        sys.exit(1)

    if len(numbers) < 2:
        print("Error: Please provide at least 2 numbers")
        sys.exit(1)

    stats = calculate_stats(numbers)
    print(f"Statistics for {len(numbers)} numbers:")
    print(format_stats(stats))


if __name__ == "__main__":
    main()
