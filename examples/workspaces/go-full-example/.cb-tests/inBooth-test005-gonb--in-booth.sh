#!/bin/bash
# Test: the GoNB notebook kernel runs a cell

echo "=== Testing the GoNB kernel ==="
cd "$(dirname "$0")/.."
python - <<'PY'
import jupyter_client

km, kc = jupyter_client.manager.start_new_kernel(kernel_name="go")
try:
    out = []
    def collect(msg):
        if msg["msg_type"] == "stream":
            out.append(msg["content"]["text"])
        elif msg["msg_type"] == "error":
            out.append("ERROR " + msg["content"]["ename"] + ": " + msg["content"]["evalue"])
    reply = kc.execute_interactive('%%\nfmt.Printf("booth %d\\n", 6*7)', timeout=300, output_hook=collect)
    text = "".join(out)
    assert reply["content"]["status"] == "ok" and "booth 42" in text, f"cell gave {reply['content']['status']}: {text!r}"
    print("GoNB OK: " + text.strip())
finally:
    kc.stop_channels()
    km.shutdown_kernel(now=True)
PY
