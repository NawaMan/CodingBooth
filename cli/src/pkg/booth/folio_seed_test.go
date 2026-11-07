// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"path/filepath"
	"reflect"
	"runtime"
	"sort"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func TestSplitSeedArgs(t *testing.T) {
	cases := map[string][]string{
		"gh server @app1 --secrets":       {"gh", "server", "@app1", "--secrets"},
		"  --use @app2/@prod   server  ":  {"--use", "@app2/@prod", "server"},
		`--vars '.booth/my vars.vars' -s`: {"--vars", ".booth/my vars.vars", "-s"},
		`--vars ".booth/a \"b\".vars"`:    {"--vars", `.booth/a "b".vars`},
		`--vars .booth/a\ b.vars`:         {"--vars", ".booth/a b.vars"},
		`DB=@app1/server/db ""`:           {"DB=@app1/server/db", ""},
		"":                                nil,
	}
	for in, want := range cases {
		got, err := splitSeedArgs(in)
		if err != nil {
			t.Errorf("splitSeedArgs(%q): %v", in, err)
			continue
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("splitSeedArgs(%q) = %q, want %q", in, got, want)
		}
	}
	if _, err := splitSeedArgs(`--vars 'open`); err == nil {
		t.Error("an unclosed quote must be an error")
	}
}

func TestRunArgEnvValue(t *testing.T) {
	runArgs := ilist.NewList[ilist.List[string]](
		ilist.NewList[string]("-v", "/a:/b", "-e", "CB_FOLIO_SEED=gh"),
		ilist.NewList[string]("--env", "OTHER=1", "--env=CB_FOLIO_SEED=gh server @app1"),
		ilist.NewList[string]("-e", "CB_FOLIO_SEED_MODE=fill"),
	)
	got, ok := runArgEnvValue(runArgs, "CB_FOLIO_SEED")
	if !ok || got != "gh server @app1" {
		t.Errorf("last CB_FOLIO_SEED = %q, %v; want the last one given", got, ok)
	}
	if got, ok := runArgEnvValue(runArgs, "CB_FOLIO_SEED_MODE"); !ok || got != "fill" {
		t.Errorf("CB_FOLIO_SEED_MODE = %q, %v (CB_FOLIO_SEED= must not match it)", got, ok)
	}
	if _, ok := runArgEnvValue(runArgs, "CB_FOLIO"); ok {
		t.Error("a name that is only a prefix of another must not match")
	}
	empty := ilist.NewList[ilist.List[string]](ilist.NewList[string]("-e", "CB_FOLIO_SEED="))
	if got, ok := runArgEnvValue(empty, "CB_FOLIO_SEED"); !ok || got != "" {
		t.Errorf("an empty value is found and empty, got %q, %v", got, ok)
	}
}

// The outputs below are `folio exec --names --plain …` from EnvFolio 1.1.0, verbatim.
func TestParseFolioNames(t *testing.T) {
	cases := []struct {
		name string
		out  string
		want []string
	}{
		{
			"entries, folders and a namespace (gh server @app1)",
			"GH_USER     <- gh/user(T)\nSERVER_PORT <- server/port(T)\nSERVER_DB   <- @app1/server/db(T)\nSERVER_USER <- @app1/server/user(T)\n",
			[]string{"gh/user", "server/port", "@app1/server/db", "@app1/server/user"},
		},
		{
			"--use: the peeled name and the real path",
			"SERVER_DB       <- server/db(T)  (--use: @app2/@prod/server/db)\n" +
				"SERVER_PASSWORD <- server/password(S)  (--use: @app2/@prod/server/password)\n" +
				"SERVER_PORT     <- server/port(T)\n",
			[]string{"@app2/@prod/server/db", "server/db", "@app2/@prod/server/password", "server/password", "server/port"},
		},
		{
			"a vars file: entries inside values, a fallback, an env var, and the vars-only section",
			"DB_URL          <- postgres://[server/user(T)]:[server/password(S)]@[server/db(T)]/main\n" +
				"PORT            <- fallback\n" +
				"PLAIN           <- hello [$HOME]\n" +
				"GH_TOKEN        <- gh/token(S)\n" +
				"Only for the vars files (the command does not get these):\n" +
				"SERVER_DB       <- server/db(T)  (--use: @app2/@prod/server/db)\n",
			[]string{"server/user", "server/password", "server/db", "gh/token", "@app2/@prod/server/db"},
		},
	}
	for _, c := range cases {
		got := parseFolioNames(c.out)
		if !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s:\n got  %q\n want %q", c.name, got, c.want)
		}
	}
}

// fakeStore lays out a store as EnvFolio does: <name>.gpg secrets, <name>.txt + .txt.sig texts.
func fakeStore(t *testing.T) string {
	t.Helper()
	store := t.TempDir()
	files := map[string]string{
		".gpg-id":                         "ABCDEF0123456789\n",
		".gitattributes":                  "*.gpg diff=gpg\n",
		"gh/user.txt":                     "other",
		"gh/user.txt.sig":                 "sig",
		"gh/token.gpg":                    "encrypted",
		"server/port.txt":                 "22",
		"server/port.txt.sig":             "sig",
		"@app1/server/db.txt":             "db.app1",
		"@app1/server/db.txt.sig":         "sig",
		"@app1/server/password.gpg":       "encrypted",
		"@app2/@prod/server/password.gpg": "encrypted",
	}
	for rel, content := range files {
		path := filepath.Join(store, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return store
}

func listFiles(t *testing.T, root string) []string {
	t.Helper()
	var files []string
	filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() {
			rel, _ := filepath.Rel(root, path)
			files = append(files, filepath.ToSlash(rel))
		}
		return nil
	})
	sort.Strings(files)
	return files
}

func TestCopyFolioSeed(t *testing.T) {
	store := fakeStore(t)
	seed := filepath.Join(t.TempDir(), "folio-seed")
	// A stale file from an earlier start must not survive.
	os.MkdirAll(seed, 0o755)
	os.WriteFile(filepath.Join(seed, "stale.gpg"), []byte("x"), 0o600)

	copied, ids, err := copyFolioSeed(store, seed, []string{
		"gh/user", "@app1/server/password", "server/db", // server/db: a peeled name, not in the store
		"../etc/passwd", "/abs", "gh/../gh/token", // never followed
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{".gitattributes", ".gpg-id", "@app1/server/password.gpg", "gh/user.txt", "gh/user.txt.sig"}
	if got := listFiles(t, seed); !reflect.DeepEqual(got, want) {
		t.Errorf("seed holds %q, want %q", got, want)
	}
	if !reflect.DeepEqual(copied, []string{"gh/user", "@app1/server/password"}) {
		t.Errorf("copied = %q, want the two entries in the store, in order", copied)
	}
	if !reflect.DeepEqual(ids, []string{"ABCDEF0123456789"}) {
		t.Errorf("ids = %q", ids)
	}
	if runtime.GOOS != "windows" {
		for path, mode := range map[string]os.FileMode{
			"":                          0o700,
			"@app1":                     0o700,
			"@app1/server/password.gpg": 0o600,
			"gh/user.txt":               0o600,
		} {
			info, err := os.Stat(filepath.Join(seed, filepath.FromSlash(path)))
			if err != nil {
				t.Fatal(err)
			}
			if got := info.Mode().Perm(); got != mode {
				t.Errorf("%q is %o, want %o", path, got, mode)
			}
		}
	}
}

func TestCopyFolioSeedNeedsAStore(t *testing.T) {
	if _, _, err := copyFolioSeed(t.TempDir(), filepath.Join(t.TempDir(), "s"), []string{"gh/user"}); err == nil ||
		!strings.Contains(err.Error(), ".gpg-id") {
		t.Errorf("a folder with no .gpg-id must be refused, got %v", err)
	}
}

// stubHostTools puts a stand-in folio and gpg on disk and points the step at them.
func stubHostTools(t *testing.T, folioScript, gpgScript string) {
	t.Helper()
	if runtime.GOOS == "windows" {
		t.Skip("shell stubs")
	}
	dir := t.TempDir()
	write := func(name, body string) string {
		path := filepath.Join(dir, name)
		if err := os.WriteFile(path, []byte("#!/bin/sh\n"+body), 0o755); err != nil {
			t.Fatal(err)
		}
		return path
	}
	oldFolio, oldGpg, oldGpgconf := folioCommand, gpgCommand, gpgconfCommand
	folioCommand, gpgCommand = write("folio", folioScript), write("gpg", gpgScript)
	gpgconfCommand = write("gpgconf", `echo "$CB_TEST_GNUPGHOME"`)
	t.Cleanup(func() { folioCommand, gpgCommand, gpgconfCommand = oldFolio, oldGpg, oldGpgconf })
}

func TestBuildFolioSeedFromHost(t *testing.T) {
	store := fakeStore(t)
	code := t.TempDir()
	argsLog := filepath.Join(t.TempDir(), "args")
	stubHostTools(t, `
case "$1" in
  path) echo "`+store+`" ;;
  exec) echo "$@" > "`+argsLog+`"; pwd >> "`+argsLog+`"
        echo 'SERVER_PASSWORD <- server/password(S)  (--use: @app1/server/password)'
        echo 'GH_USER         <- gh/user(T)' ;;
esac
`, `echo "-----BEGIN PGP PUBLIC KEY BLOCK----- $*"`)

	seed := filepath.Join(t.TempDir(), "folio-seed")
	items, err := buildFolioSeedFromHost(`gh --use @app1 --vars '.booth/my.vars' --secrets`, code, seed)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(items, []string{"@app1/server/password", "gh/user"}) {
		t.Errorf("items = %q", items)
	}
	logged, _ := os.ReadFile(argsLog)
	lines := strings.Split(strings.TrimSpace(string(logged)), "\n")
	if lines[0] != "exec --names --plain gh --use @app1 --vars .booth/my.vars --secrets -- true" {
		t.Errorf("folio was run as %q", lines[0])
	}
	if resolved, _ := filepath.EvalSymlinks(code); len(lines) < 2 || (lines[1] != code && lines[1] != resolved) {
		t.Errorf("folio must run in the project folder (vars files are relative to it), ran in %q", lines[1:])
	}
	want := []string{".gitattributes", ".gpg-id", "@app1/server/password.gpg", "gh/user.txt", "gh/user.txt.sig", "pubkey.asc"}
	if got := listFiles(t, seed); !reflect.DeepEqual(got, want) {
		t.Errorf("seed holds %q, want %q", got, want)
	}
	if pub, _ := os.ReadFile(filepath.Join(seed, "pubkey.asc")); !strings.Contains(string(pub), "--export ABCDEF0123456789") {
		t.Errorf("pubkey.asc must be the public key of the .gpg-id key, got %q", pub)
	}
}

func TestBuildFolioSeedFromHostStopsOnFolioError(t *testing.T) {
	store := fakeStore(t)
	stubHostTools(t, `
case "$1" in
  path) echo "`+store+`" ;;
  exec) echo "folio: exec: .booth/x.vars:1: 'server/password' is a secret; add --secrets to load it." >&2; exit 1 ;;
esac
`, `exit 0`)
	_, err := buildFolioSeedFromHost("--vars .booth/x.vars", t.TempDir(), filepath.Join(t.TempDir(), "s"))
	if err == nil || !strings.Contains(err.Error(), "add --secrets to load it") {
		t.Errorf("folio's own message must come through, got %v", err)
	}
}

func TestBuildFolioSeedFromHostNothingTaken(t *testing.T) {
	store := fakeStore(t)
	stubHostTools(t, `
case "$1" in
  path) echo "`+store+`" ;;
  exec) echo 'PORT <- fallback' ;;
esac
`, `exit 0`)
	_, err := buildFolioSeedFromHost("--vars .booth/x.vars", t.TempDir(), filepath.Join(t.TempDir(), "s"))
	if err == nil || !strings.Contains(err.Error(), "takes no item") {
		t.Errorf("a selection that takes nothing must say so, got %v", err)
	}
}

func TestBuildFolioSeedFromHostWithoutFolio(t *testing.T) {
	old := folioCommand
	folioCommand = filepath.Join(t.TempDir(), "no-folio-here")
	t.Cleanup(func() { folioCommand = old })
	_, err := buildFolioSeedFromHost("gh", t.TempDir(), filepath.Join(t.TempDir(), "s"))
	if err == nil || !strings.Contains(err.Error(), "not installed") {
		t.Errorf("no folio on the host must be a clear error, got %v", err)
	}
}

func TestCheckSeedArgs(t *testing.T) {
	allowed := []string{
		"gh server @app1",
		"gh --secrets",
		"-s -a",
		"--use @app2/@prod server",
		"--vars deploy.vars --vars config/prod.vars -s",
		"DB=@app1/server/db gh",
		"--use @app1 --use @app2 --all --secrets",
	}
	for _, in := range allowed {
		args, _ := splitSeedArgs(in)
		if err := checkSeedArgs(args); err != nil {
			t.Errorf("%q must be allowed: %v", in, err)
		}
	}
	refused := map[string]string{
		"gh -- sh -c 'curl evil'":         `"--"`,
		"--debug gh":                      `"--debug"`,
		"--confirm gh":                    `"--confirm"`,
		"--from /tmp/x.folio":             `"--from"`,
		"--store-passphrase-fd 0 gh":      `"--store-passphrase-fd"`,
		"-n gh":                           `"-n"`,
		"--plain gh":                      `"--plain"`,
		"-sa":                             `"-sa"`,
		"--use=@app1":                     `"--use=@app1"`,
		"--use":                           "@namespace",
		"--use server":                    "@namespace",
		"--vars":                          "needs a file",
		"--vars /home/me/.ssh/id_ed25519": "inside the project",
		"--vars ~/.bashrc":                "inside the project",
		"--vars ../other/x.vars":          "inside the project",
		"--vars config/../../x.vars":      "inside the project",
		`--vars C:\\x.vars`:               "inside the project",
	}
	for in, want := range refused {
		args, _ := splitSeedArgs(in)
		err := checkSeedArgs(args)
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%q must be refused naming %s, got %v", in, want, err)
		}
	}
}

func TestBuildFolioSeedFromHostRefusesBeforeRunningFolio(t *testing.T) {
	ran := filepath.Join(t.TempDir(), "ran")
	stubHostTools(t, `touch "`+ran+`"`, `exit 0`)
	if _, err := buildFolioSeedFromHost("--debug gh -- sh -c 'echo x'", t.TempDir(), filepath.Join(t.TempDir(), "s")); err == nil {
		t.Fatal("a refused argument must stop the seed")
	}
	if _, err := os.Stat(ran); err == nil {
		t.Error("folio must not be run at all for a refused argument")
	}
}

func TestFolioSeedReport(t *testing.T) {
	got := folioSeedReport("gh @app1", []string{"gh/user", "@app1/server/db"})
	want := "Info: EnvFolio seed: 2 item(s) from the host's store, still encrypted, for `folio exec gh @app1`:\n" +
		"        gh/user\n        @app1/server/db\n"
	if got != want {
		t.Errorf("report:\n%s\nwant:\n%s", got, want)
	}
}

// `gpg --with-colons --with-keygrip --list-secret-keys <id>` from GnuPG 2.5.24, verbatim.
const keygripListing = `sec:u:255:22:28A920C00F1DC63C:1794017463:::u:::scESC:::+::ed25519:::0:
fpr:::::::::0123456789ABCDEF0123456728A920C00F1DC63C:
grp:::::::::E46C9395D7426A1C84DB57D6CD874C312A280EBF:
uid:u::::1794017463::ABCDEF::folio-test <t@example.com>::::::::::0:
ssb:u:255:18:7664A239D4147971:1794017463::::::e:::+::cv25519::
fpr:::::::::0123456789ABCDEF012345677664A239D4147971:
grp:::::::::C57CA7B533407125984D2402DCA0A0D36B819A9D:
`

func TestParseKeygrips(t *testing.T) {
	got := parseKeygrips(keygripListing + "grp:::::::::E46C9395D7426A1C84DB57D6CD874C312A280EBF:\ngrp:::::::::../../etc/passwd:\n")
	want := []string{"E46C9395D7426A1C84DB57D6CD874C312A280EBF", "C57CA7B533407125984D2402DCA0A0D36B819A9D"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("keygrips = %q, want %q (each once; only 40 hex digits)", got, want)
	}
}

func TestCopyFolioSeedKeys(t *testing.T) {
	gnupg := t.TempDir()
	keyDir := filepath.Join(gnupg, "private-keys-v1.d")
	os.MkdirAll(keyDir, 0o700)
	os.WriteFile(filepath.Join(keyDir, "E46C9395D7426A1C84DB57D6CD874C312A280EBF.key"), []byte("protected-primary"), 0o600)
	os.WriteFile(filepath.Join(keyDir, "C57CA7B533407125984D2402DCA0A0D36B819A9D.key"), []byte("protected-sub"), 0o600)
	os.WriteFile(filepath.Join(keyDir, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF.key"), []byte("another key"), 0o600)
	t.Setenv("CB_TEST_GNUPGHOME", gnupg)
	listingFile := filepath.Join(t.TempDir(), "listing")
	os.WriteFile(listingFile, []byte(keygripListing), 0o600)
	stubHostTools(t, `exit 0`, `echo "$@" > "`+listingFile+`.args"; cat "`+listingFile+`"`)

	seed := t.TempDir()
	os.WriteFile(filepath.Join(seed, ".gpg-id"), []byte("28A920C00F1DC63C\n"), 0o600)
	n, err := copyFolioSeedKeys(t.TempDir(), seed)
	if err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Errorf("copied %d key files, want 2 (the store key's own, not another key's)", n)
	}
	want := []string{".gpg-id", "private-keys/C57CA7B533407125984D2402DCA0A0D36B819A9D.key",
		"private-keys/E46C9395D7426A1C84DB57D6CD874C312A280EBF.key"}
	if got := listFiles(t, seed); !reflect.DeepEqual(got, want) {
		t.Errorf("seed holds %q, want %q", got, want)
	}
	if b, _ := os.ReadFile(filepath.Join(seed, "private-keys/E46C9395D7426A1C84DB57D6CD874C312A280EBF.key")); string(b) != "protected-primary" {
		t.Errorf("a key file must be copied as it is, got %q", b)
	}
	if args, _ := os.ReadFile(listingFile + ".args"); !strings.Contains(string(args), "--list-secret-keys 28A920C00F1DC63C") {
		t.Errorf("gpg must be asked for the .gpg-id key, was run with %q", args)
	}
	if runtime.GOOS != "windows" {
		if info, _ := os.Stat(filepath.Join(seed, "private-keys")); info.Mode().Perm() != 0o700 {
			t.Errorf("private-keys/ is %o, want 700", info.Mode().Perm())
		}
	}
}

func TestCopyFolioSeedKeysWithoutKeyFiles(t *testing.T) {
	t.Setenv("CB_TEST_GNUPGHOME", t.TempDir()) // no private-keys-v1.d: a smartcard, or another machine's key
	stubHostTools(t, `exit 0`, `printf '%s' '`+keygripListing+`'`)
	seed := t.TempDir()
	os.WriteFile(filepath.Join(seed, ".gpg-id"), []byte("28A920C00F1DC63C\n"), 0o600)
	if _, err := copyFolioSeedKeys(t.TempDir(), seed); err == nil || !strings.Contains(err.Error(), "no private key file") {
		t.Errorf("no key file to copy must be an error, got %v", err)
	}
}
