// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// Folio seed (envfolio+seed): the booth gets a copy of some items of the host's EnvFolio store,
// still encrypted, and the store's key to open them -- never the whole store, never another key.
//
// The extension passes the items as `folio exec` arguments in run-args (-e CB_FOLIO_SEED=…), the
// only way a template param reaches the host side. Before the container starts, the host's
// `folio exec --names --plain <args> -- true` says which entries those arguments take -- nothing
// is read or decrypted, the key is not unlocked -- and each one is copied, at its own path, into
// .booth/.tmp/folio-seed/ with the store's .gpg-id and its public key. The booth sees that folder
// through its .booth mount; the envfolio startup hook makes it the booth's store (CB_FOLIO_SEED_MODE
// says when). Paths keep their namespaces (@app2/@prod/…), so the same `folio exec --use …` means
// the same thing in the booth and on the host.
//
// The store key comes too, so folio in the booth decrypts on its own (a remote or cloud booth has
// no host to ask): its private key files, still protected by the passphrase, go the way every key
// reaches a booth -- .booth/.tmp/gnupg-keys/ (see gnupg_keys.go), imported by the gnupg hook.
const (
	folioSeedEnv     = "CB_FOLIO_SEED"
	folioSeedDirName = "folio-seed"
	folioSeedPubKey  = "pubkey.asc"
)

// folioCommand and gpgCommand are the host commands, variables so tests can stand in for them.
var (
	folioCommand   = "folio"
	gpgCommand     = "gpg"
	gpgconfCommand = "gpgconf"
)

// PrepareFolioSeed builds .booth/.tmp/folio-seed/ when run-args ask for a seed. It runs after
// PrepareBoothTmp, which empties .booth/.tmp/ first, so a seed is always this start's. A seed that
// cannot be made stops the start: a booth missing the items it was set up with is not what was
// asked for, and folio's own message says what to fix.
func PrepareFolioSeed(ctx appctx.AppContext) (appctx.AppContext, error) {
	spec, ok := runArgEnvValue(ctx.RunArgs(), folioSeedEnv)
	if !ok || strings.TrimSpace(spec) == "" {
		return ctx, nil
	}
	if ctx.Dryrun() {
		fmt.Fprintf(os.Stderr, "Info: would seed the booth's EnvFolio store with: folio exec %s\n", spec)
		return ctx, nil
	}
	boothDir := hostBoothDir(ctx)
	if info, err := os.Stat(boothDir); boothDir == "" || err != nil || !info.IsDir() {
		return ctx, fmt.Errorf("folio seed: the booth has no .booth folder to put the seed in (%s)", boothDir)
	}
	seedDir := filepath.Join(boothDir, ".tmp", folioSeedDirName)
	items, err := buildFolioSeedFromHost(spec, ctx.Code(), seedDir)
	if err != nil {
		os.RemoveAll(seedDir)
		return ctx, fmt.Errorf("folio seed: %w", err)
	}
	// Every start says what came in, so a selection that takes more than meant is seen.
	fmt.Fprint(os.Stderr, folioSeedReport(spec, items))
	// The store key. One that cannot be copied (on a smartcard) does not stop the seed: the items
	// still come and the texts still read; only the secrets need the key brought another way.
	keys, err := copyFolioSeedKey(ctx.Code(), seedDir, gnupgKeysDir(boothDir))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: EnvFolio seed: the store key could not be brought (%v); "+
			"its secrets cannot be opened in the booth.\n", err)
	} else {
		fmt.Fprintf(os.Stderr, "Info: EnvFolio seed: and %d private key file(s) of the store key, "+
			"still protected by its passphrase.\n", keys)
	}
	return ctx, nil
}

// copyFolioSeedKey copies the private key files of the key(s) in the seed's .gpg-id into the
// booth's key folder (gnupgKeysDir).
func copyFolioSeedKey(codePath, seedDir, keysDir string) (int, error) {
	idData, err := os.ReadFile(filepath.Join(seedDir, ".gpg-id"))
	if err != nil {
		return 0, err
	}
	return copyHostPrivateKeys(codePath, strings.Fields(string(idData)), filepath.Join(keysDir, gnupgPrivateKeysDir))
}

// folioSeedReport lists the items a seed copied, one per line.
func folioSeedReport(spec string, items []string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "Info: EnvFolio seed: %d item(s) from the host's store, still encrypted, for `folio exec %s`:\n", len(items), spec)
	for _, item := range items {
		fmt.Fprintf(&b, "        %s\n", item)
	}
	return b.String()
}

// buildFolioSeedFromHost asks the host's folio which entries spec takes, then copies them.
func buildFolioSeedFromHost(spec, codePath, seedDir string) ([]string, error) {
	args, err := splitSeedArgs(spec)
	if err != nil {
		return nil, err
	}
	if err := checkSeedArgs(args); err != nil {
		return nil, err
	}
	if _, err := exec.LookPath(folioCommand); err != nil {
		return nil, fmt.Errorf("EnvFolio (%s) is not installed on this machine, so the items for `folio exec %s` cannot be found", folioCommand, spec)
	}
	storeOut, err := runHost(codePath, folioCommand, "path")
	if err != nil {
		return nil, fmt.Errorf("`%s path` failed: %w", folioCommand, err)
	}
	storeDir := strings.TrimSpace(storeOut)

	names := append([]string{"exec", "--names", "--plain"}, args...)
	names = append(names, "--", "true")
	out, err := runHost(codePath, folioCommand, names...)
	if err != nil {
		return nil, fmt.Errorf("`folio exec --names %s` failed: %w", spec, err)
	}
	entries := parseFolioNames(out)
	items, ids, err := copyFolioSeed(storeDir, seedDir, entries)
	if err != nil {
		return nil, err
	}
	if len(items) == 0 {
		return nil, fmt.Errorf("`folio exec %s` takes no item from the store at %s", spec, storeDir)
	}
	// The texts are signed by the store's key: the booth needs its public half to read them.
	// Without it the secrets still come; only reading a text fails, so this is a warning.
	if err := exportHostPublicKeys(codePath, filepath.Join(seedDir, folioSeedPubKey), ids); err != nil {
		fmt.Fprintf(os.Stderr, "Warning: folio seed: could not export the store's public key (%v); "+
			"texts will not verify in the booth.\n", err)
	}
	return items, nil
}

// checkSeedArgs lets through only what names items: entries, VAR=<name>, -s/--secrets, -a/--all,
// --use <@namespace> and --vars <file>, the file inside the project. FOLIO_SEED comes from the
// project's config, which may be someone else's, and these arguments go to a command on the
// host: anything else -- `--`, --debug, --confirm, --from, the --*-fd options, an unknown flag --
// is refused here, rather than trusting that folio's --names keeps them harmless.
func checkSeedArgs(args []string) error {
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch arg {
		case "-s", "--secrets", "-a", "--all":
			continue
		case "--use":
			if i+1 >= len(args) || !strings.HasPrefix(args[i+1], "@") {
				return fmt.Errorf("--use needs an @namespace after it, e.g. --use @app2/@prod")
			}
			i++
			continue
		case "--vars":
			if i+1 >= len(args) {
				return fmt.Errorf("--vars needs a file after it")
			}
			if !isProjectRelative(args[i+1]) {
				return fmt.Errorf("--vars %s: the vars file must be a path inside the project (relative, no ..), "+
					"where the booth can read it too", args[i+1])
			}
			i++
			continue
		}
		if strings.HasPrefix(arg, "-") {
			return fmt.Errorf("%q is not allowed in FOLIO_SEED: only entries, VAR=<name>, --secrets, --all, "+
				"--use <@namespace> and --vars <file> name what to copy", arg)
		}
	}
	return nil
}

// isProjectRelative: a relative path that stays in the folder it is relative to.
func isProjectRelative(path string) bool {
	if path == "" || filepath.IsAbs(path) || strings.HasPrefix(path, "/") || strings.HasPrefix(path, "~") ||
		strings.Contains(path, "\\") || (len(path) > 1 && path[1] == ':') {
		return false
	}
	for _, part := range strings.Split(path, "/") {
		if part == ".." {
			return false
		}
	}
	return true
}

// runHost runs a host command in dir and returns its stdout; on failure the error carries its
// stderr, which for folio is the message that says what to fix.
func runHost(dir, name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdin = nil
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return "", fmt.Errorf("%s", msg)
		}
		return "", err
	}
	return stdout.String(), nil
}

// runArgEnvValue returns the value of the last `-e NAME=value` (or --env, --env=…) in runArgs.
func runArgEnvValue(runArgs ilist.List[ilist.List[string]], name string) (string, bool) {
	values := runArgEnvValues(runArgs, name)
	if len(values) == 0 {
		return "", false
	}
	return values[len(values)-1], true
}

// splitSeedArgs splits the seed's `folio exec` arguments as a shell would: on blanks, with
// '…' and "…" keeping a vars file path with a space in it whole, and \ escaping one character.
func splitSeedArgs(s string) ([]string, error) {
	var args []string
	var cur strings.Builder
	inArg := false
	var quote rune
	escaped := false
	for _, r := range s {
		switch {
		case escaped:
			cur.WriteRune(r)
			escaped = false
		case quote != 0:
			if r == quote {
				quote = 0
			} else if r == '\\' && quote == '"' {
				escaped = true
			} else {
				cur.WriteRune(r)
			}
		case r == '\\':
			escaped, inArg = true, true
		case r == '\'' || r == '"':
			quote, inArg = r, true
		case r == ' ' || r == '\t' || r == '\n':
			if inArg {
				args = append(args, cur.String())
				cur.Reset()
				inArg = false
			}
		default:
			cur.WriteRune(r)
			inArg = true
		}
	}
	if quote != 0 {
		return nil, fmt.Errorf("unclosed %c in the seed's folio arguments: %s", quote, s)
	}
	if escaped {
		cur.WriteRune('\\')
	}
	if inArg {
		args = append(args, cur.String())
	}
	return args, nil
}

var (
	// "(--use: @app2/@prod/server/db)": the entry's real path, after a peeled name.
	folioUseNote = regexp.MustCompile(`\(--use: ([^)\s]+)\)`)
	// "server/db(T)", "[gh/token(S)]": an entry named by its path, alone or inside a value.
	folioEntryMark = regexp.MustCompile(`([^\s\[\]()]+)\((?:S|T)\)`)
)

// parseFolioNames reads `folio exec --names --plain` and returns the store paths it names, each
// once, in order. Under --use a line shows the peeled name and then the real path in a note; both
// are kept, and copyFolioSeed takes only those that are in the store (a peeled name usually is
// not; when it is, the extra item changes nothing: folio picks the same one in the booth). A
// fallback value names no path, so nothing is copied for it.
func parseFolioNames(out string) []string {
	var names []string
	seen := map[string]bool{}
	add := func(n string) {
		if n != "" && !seen[n] {
			seen[n] = true
			names = append(names, n)
		}
	}
	for _, line := range strings.Split(out, "\n") {
		for _, m := range folioUseNote.FindAllStringSubmatch(line, -1) {
			add(m[1])
		}
		for _, m := range folioEntryMark.FindAllStringSubmatch(folioUseNote.ReplaceAllString(line, ""), -1) {
			add(m[1])
		}
	}
	return names
}

// copyFolioSeed makes seedDir afresh: the store's .gpg-id (and .gitattributes), then for each entry that is in the
// store, its secret (<name>.gpg) or its text (<name>.txt and <name>.txt.sig), at the same path.
// Folders are 700 and files 600, as in a store. It returns the entries it copied and the key
// ids in .gpg-id. A name that would leave the store (.., an absolute path) is never followed.
func copyFolioSeed(storeDir, seedDir string, entries []string) ([]string, []string, error) {
	idFile := filepath.Join(storeDir, ".gpg-id")
	idData, err := os.ReadFile(idFile)
	if err != nil || len(bytes.TrimSpace(idData)) == 0 {
		return nil, nil, fmt.Errorf("%s is not an EnvFolio store: it has no .gpg-id", storeDir)
	}
	if err := os.RemoveAll(seedDir); err != nil {
		return nil, nil, err
	}
	if err := os.MkdirAll(seedDir, 0o700); err != nil {
		return nil, nil, err
	}
	if err := os.Chmod(seedDir, 0o700); err != nil {
		return nil, nil, err
	}
	if err := os.WriteFile(filepath.Join(seedDir, ".gpg-id"), idData, 0o600); err != nil {
		return nil, nil, err
	}
	// pass writes it at init (*.gpg diff=gpg); a store made from the seed should look the same.
	if isRegularFile(filepath.Join(storeDir, ".gitattributes")) {
		if err := copyStoreFile(storeDir, seedDir, ".gitattributes"); err != nil {
			return nil, nil, err
		}
	}
	var ids []string
	for _, id := range strings.Split(string(idData), "\n") {
		if id = strings.TrimSpace(id); id != "" {
			ids = append(ids, id)
		}
	}

	var copied []string
	for _, name := range entries {
		if !isStoreRelative(name) {
			continue
		}
		var files []string
		base := filepath.Join(storeDir, filepath.FromSlash(name))
		if isRegularFile(base + ".gpg") {
			files = append(files, name+".gpg")
		}
		if isRegularFile(base + ".txt") {
			files = append(files, name+".txt")
			if isRegularFile(base + ".txt.sig") {
				files = append(files, name+".txt.sig")
			}
		}
		if len(files) == 0 {
			continue
		}
		for _, f := range files {
			if err := copyStoreFile(storeDir, seedDir, f); err != nil {
				return nil, nil, err
			}
		}
		copied = append(copied, name)
	}
	return copied, ids, nil
}

func isStoreRelative(name string) bool {
	if name == "" || strings.HasPrefix(name, "/") || strings.Contains(name, "\\") || filepath.IsAbs(name) {
		return false
	}
	for _, part := range strings.Split(name, "/") {
		if part == "" || part == "." || part == ".." {
			return false
		}
	}
	return true
}

func isRegularFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

func copyStoreFile(storeDir, seedDir, rel string) error {
	dst := filepath.Join(seedDir, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return err
	}
	in, err := os.Open(filepath.Join(storeDir, filepath.FromSlash(rel)))
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

