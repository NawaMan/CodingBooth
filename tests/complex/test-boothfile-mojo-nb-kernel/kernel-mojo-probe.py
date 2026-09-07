#!/usr/bin/env python
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

"""Drive the Mojo-named Python kernel and run a %%mojo cell.

Prints one line the test script can grep:

    PROBE text=<payload> error=<yes|no>
"""

from jupyter_client.manager import start_new_kernel

MOJO_CELL = """%%mojo

def main():
    print("Hello from Mojo")
"""


def drain(kc, msg_id, timeout=120):
    texts = []
    err = False
    while True:
        msg = kc.get_iopub_msg(timeout=timeout)
        if msg["parent_header"].get("msg_id") != msg_id:
            continue
        msg_type, content = msg["msg_type"], msg["content"]
        if msg_type == "stream":
            texts.append(content.get("text", ""))
        elif msg_type in ("display_data", "execute_result"):
            if "text/plain" in content.get("data", {}):
                texts.append(content["data"]["text/plain"])
        elif msg_type == "error":
            err = True
            texts.append("ERROR: " + "\n".join(content.get("traceback", [])))
        elif msg_type == "status" and content.get("execution_state") == "idle":
            break
    return "".join(texts), err


def main() -> int:
    km, kc = start_new_kernel(kernel_name="mojo")
    try:
        drain(kc, kc.execute("import mojo.notebook"))
        out, err = drain(kc, kc.execute(MOJO_CELL))
    finally:
        kc.stop_channels()
        km.shutdown_kernel()

    print("PROBE text=%r error=%s" % (out[:400], "yes" if err else "no"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
