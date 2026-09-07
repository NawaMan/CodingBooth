#!/bin/bash
echo "=== Testing Factorial notebook ==="
cd "$(dirname "$0")/.."
python << 'PY'
import nbformat
from nbclient import NotebookClient

nb = nbformat.read("Factorial.ipynb", as_version=4)
NotebookClient(nb, kernel_name="mojo", timeout=180).execute()
text = []
for cell in nb.cells:
    for out in cell.get("outputs", []):
        if out.get("name") == "stdout":
            t = out.get("text", "")
            text.append("".join(t) if isinstance(t, list) else t)
        data = out.get("data") or {}
        if "text/plain" in data:
            t = data["text/plain"]
            text.append("".join(t) if isinstance(t, list) else t)
joined = "\n".join(text)
assert "Hello from Mojo" in joined, joined
assert "5! = 120" in joined, joined
print("notebook ok")
PY
