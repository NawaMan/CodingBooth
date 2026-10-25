#!/bin/bash
echo "=== Testing the blueprint: web, PDF, dependency graph, declaration check ==="
cd "$(dirname "$0")/.."
rm -rf blueprint/web blueprint/print blueprint/lean_decls
fail=0
just web >/tmp/bp-web.out 2>&1 || { echo "  ✗ just web failed"; tail -20 /tmp/bp-web.out; fail=1; }
just pdf >/tmp/bp-pdf.out 2>&1 || { echo "  ✗ just pdf failed"; tail -20 /tmp/bp-pdf.out; fail=1; }
[[ -s blueprint/web/index.html ]]       && echo "  ✓ web version"   || { echo "  ✗ no blueprint/web/index.html"; fail=1; }
[[ -s blueprint/print/print.pdf ]]      && echo "  ✓ PDF version"   || { echo "  ✗ no blueprint/print/print.pdf"; fail=1; }

# The graph colours each node by its state. Proof and all ancestors formalized: #1CAC78.
# Proof ready to formalize: #A3D6FF.
graph="$(cat blueprint/web/dep_graph_document.html 2>/dev/null)"
node() { grep -oE "\"$1\"[^;]*fillcolor=\"#[0-9A-F]+\"" <<< "$graph" | grep -oE '#[0-9A-F]+'; }
[[ "$(node thm:oddSum_eq_sq)" == "#1CAC78" ]] && echo "  ✓ oddSum_eq_sq is shown fully proved" \
    || { echo "  ✗ oddSum_eq_sq colour: $(node thm:oddSum_eq_sq)"; fail=1; }
[[ "$(node thm:nicomachus)" == "#A3D6FF" ]] && echo "  ✓ Nicomachus is shown as still to prove" \
    || { echo "  ✗ nicomachus colour: $(node thm:nicomachus)"; fail=1; }

just checkdecls >/tmp/bp-decls.out 2>&1 && echo "  ✓ every \\lean name exists ($(grep -c . blueprint/lean_decls) names)" \
    || { echo "  ✗ checkdecls failed"; cat /tmp/bp-decls.out; fail=1; }
exit $fail
