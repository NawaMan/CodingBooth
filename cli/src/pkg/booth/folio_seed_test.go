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

	count, ids, err := copyFolioSeed(store, seed, []string{
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
	if count != 2 {
		t.Errorf("count = %d, want 2", count)
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
	oldFolio, oldGpg := folioCommand, gpgCommand
	folioCommand, gpgCommand = write("folio", folioScript), write("gpg", gpgScript)
	t.Cleanup(func() { folioCommand, gpgCommand = oldFolio, oldGpg })
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
	count, err := buildFolioSeedFromHost(`gh --use @app1 --vars '.booth/my.vars' --secrets`, code, seed)
	if err != nil {
		t.Fatal(err)
	}
	if count != 2 {
		t.Errorf("count = %d, want 2", count)
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
