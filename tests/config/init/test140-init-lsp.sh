#!/bin/bash
# lsp: language servers by curated extension (lsp+markdown) or by typed name
# (lsp:taplo,yaml), each extension adding its VS Code half; neovim+lsp wires
# Neovim's client to them.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# --- typed names: canonicalized (deduped, sorted) into the one install line ---
run booth config $prj --no-tui --select "lsp:taplo,marksman,taplo"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg LSP_SERVERS=" 'marksman,taplo'                       "typed server names are deduped and sorted"
assert-line "$boothfile" "install lsp " '${LSP_SERVERS}'                           "install lsp line"

# --- a version pin rides along on the name ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "lsp:taplo@0.10.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg LSP_SERVERS=" 'taplo@0.10.0'                         "server@version pin"

# --- a curated extension: the server, then its VS Code extension ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "lsp+markdown"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg LSP_SERVERS=" ''                                     "no typed names leaves the list empty"
assert-line "$boothfile" "setup lsp--marksman" ''                                  "lsp+markdown sets up marksman"
assert-line "$boothfile" "setup markdown-code-extension" ''                        "lsp+markdown adds markdownlint for VS Code"

# --- a Node-based server pulls in its runtime ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "lsp+yaml"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup nodejs " '${NODE_VERSION}'                         "lsp+yaml requires nodejs"
TEST_COUNT=$((TEST_COUNT + 1))
NODE_LINE=$(grep -n '^setup nodejs ' "$boothfile" | head -1 | cut -d: -f1)
YAML_LINE=$(grep -n '^setup lsp--yaml' "$boothfile" | head -1 | cut -d: -f1)
if [[ -n "$NODE_LINE" && -n "$YAML_LINE" && "$YAML_LINE" -gt "$NODE_LINE" ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -n "Test ${TEST_COUNT}: the npm server is set up after nodejs .......................... "
  echo -e "\033[32mPASSED\033[0m"
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: the npm server is set up after nodejs")
  echo -n "Test ${TEST_COUNT}: the npm server is set up after nodejs .......................... "
  echo -e "\033[31mFAILED\033[0m"
  echo "  setup nodejs line: ${NODE_LINE:-<none>}, setup lsp--yaml line: ${YAML_LINE:-<none>}"
fi

# --- C/C++ and Java ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "lsp+c+java"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup lsp--clangd" ''                                    "lsp+c sets up clangd"
assert-line "$boothfile" "setup clang-code-extension" ''                           "lsp+c adds the clangd VS Code extension"
assert-line "$boothfile" "setup lsp--jdtls" ''                                     "lsp+java sets up jdtls"
assert-line "$boothfile" "setup jdk " '${JDK_VERSION} ${JDK_VENDOR}'               "lsp+java requires java"

# --- React and Svelte ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "lsp+react+svelte"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup lsp--typescript" ''                                "lsp+react uses the TypeScript server"
assert-line "$boothfile" "setup react-code-extension" ''                           "lsp+react adds React snippets"
assert-line "$boothfile" "setup lsp--svelte" ''                                    "lsp+svelte sets up svelte-language-server"
assert-line "$boothfile" "setup svelte-code-extension" ''                          "lsp+svelte adds Svelte for VS Code"

# --- Neovim's client ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "neovim+lsp"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup neovim-lsp" ''                                     "neovim+lsp wires the client"

finally
