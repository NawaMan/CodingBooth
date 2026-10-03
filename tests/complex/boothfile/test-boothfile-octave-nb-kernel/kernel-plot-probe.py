#!/usr/bin/env python
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

"""Drive the Octave kernel over the real Jupyter protocol and report on a plot.

Run inside the booth. Executes a plotting cell against the registered `octave`
kernel and prints one summary line the test script can grep:

    PROBE mimetypes=<comma-list> ascii=<yes|no> warning=<yes|no>

`mimetypes` must contain `image/png` — that is the whole point of the inline
backend. `ascii=yes` means gnuplot fell back to its "dumb" terminal and dumped
text art into the cell, which is the failure this test exists to catch.
"""

import sys

from jupyter_client.manager import start_new_kernel

PLOT_CELL = """
x = 1:20;
y = 2 * x + 3;
plot(x, y, 'bo', 'markersize', 8);
hold on;
plot(x, y, 'r-', 'linewidth', 2);
xlabel('x'); ylabel('y');
title('Probe');
legend('Data', 'Fit');
hold off;
"""

# gnuplot's "dumb" terminal draws with these; seeing them in a cell's text
# output means the figure was rendered as ASCII instead of an image.
ASCII_MARKERS = ("####", "+-+", "|###")


def main() -> int:
    km, kc = start_new_kernel(kernel_name="octave")
    try:
        msg_id = kc.execute(PLOT_CELL)
        texts: list[str] = []
        mimetypes: list[str] = []
        while True:
            msg = kc.get_iopub_msg(timeout=120)
            if msg["parent_header"].get("msg_id") != msg_id:
                continue
            msg_type, content = msg["msg_type"], msg["content"]
            if msg_type == "stream":
                texts.append(content["text"])
            elif msg_type in ("display_data", "execute_result"):
                mimetypes.extend(content["data"])
                if "text/plain" in content["data"]:
                    texts.append(content["data"]["text/plain"])
            elif msg_type == "error":
                texts.append("ERROR: " + "\n".join(content["traceback"]))
            elif msg_type == "status" and content["execution_state"] == "idle":
                break
    finally:
        kc.stop_channels()
        km.shutdown_kernel()

    out = "".join(texts)
    ascii_plot = any(marker in out for marker in ASCII_MARKERS)
    warned = "graphics toolkit is discouraged" in out

    print(
        "PROBE mimetypes=%s ascii=%s warning=%s"
        % (
            ",".join(sorted(set(mimetypes))) or "none",
            "yes" if ascii_plot else "no",
            "yes" if warned else "no",
        )
    )
    if out.strip():
        print("PROBE-TEXT %r" % out[:400])
    return 0


if __name__ == "__main__":
    sys.exit(main())
