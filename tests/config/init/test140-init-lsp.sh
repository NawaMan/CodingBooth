#!/bin/bash
# lsp: language servers by curated extension (lsp+markdown) or by typed name
# (lsp:taplo,yaml), each extension adding its VS Code half; neovim+lsp wires
# Neovim's client to them. lsp+markdown and neovim+lsp come selected; ~ drops them.
source "$(dirname "$0")/../test-helpers--source.sh"

# assert-no-line <file> <prefix> <message>: no line in <file> starts with <prefix>.
function assert-no-line() {
    TEST_COUNT=$((TEST_COUNT + 1))
    local label="${3} "
    local pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label}${pad} "
    if grep -q "^${2}" "$1" 2>/dev/null; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${label}")
        echo -e "\033[31mFAILED\033[0m"
        echo "  UNEXPECTED: $(grep "^${2}" "$1" | head -1)"
    else
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    fi
}

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

# --- Haskell and Zig: each server pulls in its toolchain ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "lsp+haskell+zig"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup lsp--hls" ''                                       "lsp+haskell sets up HLS"
assert-line "$boothfile" "setup haskell " '--ghc-version ${GHC_VERSION}'           "lsp+haskell requires haskell"
assert-line "$boothfile" "setup lsp--zls" ''                                       "lsp+zig sets up zls"
assert-line "$boothfile" "setup zig " '--zig-version ${ZIG_VERSION}'               "lsp+zig requires zig"

# --- markdown comes with the template, and ~ drops it ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "lsp"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup lsp--marksman" ''                                  "bare lsp auto-selects lsp+markdown"
assert-no-line "$boothfile" "setup lsp--bash"                                      "bare lsp leaves bash (and Node.js) out"
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "lsp~markdown"
boothfile="$prj/.booth/Boothfile"
assert-no-line "$boothfile" "setup lsp--marksman"                                  "lsp~markdown drops marksman"

# --- Neovim's client comes with neovim, and ~ drops it ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "neovim"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "setup neovim-lsp" ''                                     "neovim auto-selects neovim+lsp"
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "neovim~lsp"
boothfile="$prj/.booth/Boothfile"
assert-no-line "$boothfile" "setup neovim-lsp"                                     "neovim~lsp drops the client"

finally
