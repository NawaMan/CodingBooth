#!/usr/bin/env python3
"""Draw a recursive tree — the same drawing as samples/tree.logo.

    python tree.py
    xvfb-run -a python tree.py --output /tmp/tree.ps
"""
from __future__ import annotations

import argparse
import turtle_tk  # noqa: F401  — Tcl/Tk paths for booth Python
import turtle


def tree(t: turtle.Turtle, size: float) -> None:
    if size < 4:
        return
    t.forward(size)
    t.left(30)
    tree(t, size * 0.7)
    t.right(60)
    tree(t, size * 0.7)
    t.left(30)
    t.backward(size)


def draw() -> None:
    t = turtle.Turtle()
    t.hideturtle()
    t.speed(0)
    t.left(90)
    t.penup()
    t.backward(80)
    t.pendown()
    tree(t, 70)


def main() -> None:
    parser = argparse.ArgumentParser(description="Draw a tree with Python turtle")
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
