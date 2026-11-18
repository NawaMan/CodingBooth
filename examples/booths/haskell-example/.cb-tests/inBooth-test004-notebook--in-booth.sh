#!/bin/bash
echo "=== Testing the Haskell notebook kernel ==="
cd "$(dirname "$0")/.."
python - <<'PY'
import nbformat, nbclient
nb = nbformat.read("Haskell-Tour.ipynb", as_version=4)
nbclient.NotebookClient(nb, kernel_name="haskell", timeout=300).execute()
text = "\n".join(str(o.get("data", {}).get("text/plain", o.get("text", ""))) for c in nb.cells if c.cell_type == "code" for o in c.outputs)
for want in ["15511210043330985984000000", '("the",3)', '("cat",11)', "9.12.4"]:
    assert want in text, f"missing {want!r} in notebook output:\n{text}"
print("notebook OK")
PY
