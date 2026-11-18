"""Point booth Python at the Tcl/Tk bundled in its own prefix.

uv's CPython ships Tcl/Tk 9 next to the interpreter. A venv makes tkinter
look under sys.prefix instead of sys.base_prefix, and Ubuntu's apt `tk` is
8.6 — mixing the two is a version conflict. Import this module before
`turtle`.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path


def _ensure_tk_paths() -> None:
    lib = Path(sys.base_prefix) / "lib"
    for ver in ("9.0", "8.6"):
        tcl, tk = lib / f"tcl{ver}", lib / f"tk{ver}"
        if tcl.is_dir() and tk.is_dir():
            os.environ.setdefault("TCL_LIBRARY", str(tcl))
            os.environ.setdefault("TK_LIBRARY", str(tk))
            return


_ensure_tk_paths()
