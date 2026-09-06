#!/usr/bin/env python3
"""Draw a square — the same drawing as samples/square.logo.

    python square.py
    xvfb-run -a python square.py --output /tmp/square.ps
"""
from __future__ import annotations

import argparse
import turtle_tk  # noqa: F401  — Tcl/Tk paths for booth Python
import turtle


def draw() -> None:
    t = turtle.Turtle()
    t.hideturtle()
    t.speed(0)
    for _ in range(4):
        t.forward(100)
        t.right(90)


def main() -> None:
    parser = argparse.ArgumentParser(description="Draw a square with Python turtle")
    parser.add_argument("--output", help="Write PostScript to FILE and exit")
    args = parser.parse_args()

    if args.output:
        turtle.Screen().tracer(0, 0)
    draw()
    if args.output:
        turtle.getcanvas().postscript(file=args.output)
        return
    turtle.done()


if __name__ == "__main__":
    main()
