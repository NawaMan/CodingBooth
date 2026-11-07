// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// pruneProject makes a project whose .booth/cache/ holds a declared folder (~/.n8n), a declared
// file (.bash_history) and leftovers: a folder from a deselected template and a stray file.
func pruneProject(t *testing.T) string {
	t.Helper()
	code := t.TempDir()
	booth := filepath.Join(code, ".booth")
	write := func(rel, content string) {
		p := filepath.Join(booth, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(p), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	write("config.toml", "cache-files = [\"home/coder/.bash_history\"]\ncache-dirs = [\"home/coder/.n8n:0700\"]\n")
	write("cache/home/coder/.bash_history", "ls\n")
	write("cache/home/coder/.n8n/.mount-this", "")
	write("cache/home/coder/.n8n/db.sqlite", "data")
	write("cache/home/coder/.gnupg/.mount-this", "")
	write("cache/home/coder/.gnupg/private-keys-v1.d/K.key", "secret")
	write("cache/home/coder/.local/share/folio/.mount-this", "")
	write("cache/home/coder/.local/share/folio/store/.gpg-id", "K")
	write("cache/var/old.log", "x")
	return code
}

func exists(t *testing.T, p string) bool {
	t.Helper()
	_, err := os.Stat(p)
	return err == nil
}

func TestPruneData_DeletesOnlyLeftovers(t *testing.T) {
	code := pruneProject(t)
	cache := filepath.Join(code, ".booth", "cache")
	var out, errOut bytes.Buffer
	if err := pruneData("cache", code, true, nil, nil, strings.NewReader(""), &out, &errOut); err != nil {
		t.Fatalf("prune: %v\n%s%s", err, out.String(), errOut.String())
	}
	for _, gone := range []string{"home/coder/.gnupg", "home/coder/.local", "var"} {
		if exists(t, filepath.Join(cache, gone)) {
			t.Errorf("%s should be gone (with its now-empty parents)", gone)
		}
	}
	for _, kept := range []string{"home/coder/.bash_history", "home/coder/.n8n/db.sqlite"} {
		if !exists(t, filepath.Join(cache, kept)) {
			t.Errorf("declared %s must stay", kept)
		}
	}
	for _, want := range []string{".booth/cache/home/coder/.gnupg/", ".booth/cache/var/old.log", "Deleted 3 item(s)"} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("output lacks %q:\n%s", want, out.String())
		}
	}
}

func TestPruneData_AsksAndCancels(t *testing.T) {
	code := pruneProject(t)
	var out bytes.Buffer
	// No --yes and no "y" (as with no terminal: an empty stdin): nothing is deleted.
	if err := pruneData("cache", code, false, nil, nil, strings.NewReader(""), &out, &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "[y/N]") || !strings.Contains(out.String(), "Prune cancelled.") {
		t.Errorf("should ask, then cancel:\n%s", out.String())
	}
	if !exists(t, filepath.Join(code, ".booth", "cache", "home", "coder", ".gnupg")) {
		t.Errorf("a cancelled prune deletes nothing")
	}

	out.Reset()
	if err := pruneData("cache", code, false, nil, nil, strings.NewReader("y\n"), &out, &out); err != nil {
		t.Fatal(err)
	}
	if exists(t, filepath.Join(code, ".booth", "cache", "home", "coder", ".gnupg")) {
		t.Errorf("answering y deletes:\n%s", out.String())
	}
}

func TestPruneData_RefusesWhileABoothRuns(t *testing.T) {
	code := pruneProject(t)
	for _, c := range []managedContainer{
		{Name: "proj", State: "running", CodePath: code},
		{Name: "express", State: "running", CodePath: t.TempDir(), BoothDir: filepath.Join(code, ".booth")},
	} {
		var out bytes.Buffer
		err := pruneData("cache", code, true, []managedContainer{c}, nil, strings.NewReader(""), &out, &out)
		if err == nil || !strings.Contains(err.Error(), c.Name) {
			t.Errorf("should refuse while %s runs on the project, got %v", c.Name, err)
		}
	}
	if !exists(t, filepath.Join(code, ".booth", "cache", "home", "coder", ".gnupg")) {
		t.Errorf("a refused prune deletes nothing")
	}
	// A stopped booth, or one on another project, is no reason to refuse.
	others := []managedContainer{
		{Name: "proj", State: "exited", CodePath: code},
		{Name: "other", State: "running", CodePath: t.TempDir()},
	}
	var out bytes.Buffer
	if err := pruneData("cache", code, true, others, nil, strings.NewReader(""), &out, &out); err != nil {
		t.Errorf("unexpected refusal: %v", err)
	}
}

func TestPruneData_NothingAndNoBooth(t *testing.T) {
	code := t.TempDir()
	var out bytes.Buffer
	if err := pruneData("shared", code, true, nil, nil, strings.NewReader(""), &out, &out); err == nil {
		t.Errorf("a folder without .booth should be an error")
	}
	if err := os.MkdirAll(filepath.Join(code, ".booth", "shared"), 0755); err != nil {
		t.Fatal(err)
	}
	out.Reset()
	if err := pruneData("shared", code, true, nil, nil, strings.NewReader(""), &out, &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "Nothing to prune") {
		t.Errorf("got:\n%s", out.String())
	}
}

func TestPruneDataKind(t *testing.T) {
	for word, want := range map[string]string{"cache": "cache", "shared": "shared", "share": "shared"} {
		if got, ok := pruneDataKind(word); !ok || got != want {
			t.Errorf("pruneDataKind(%q) = %q, %v", word, got, ok)
		}
	}
	if _, ok := pruneDataKind("home"); ok {
		t.Errorf("only cache and shared are data prunes")
	}
}

func TestPrune_RejectsOtherArguments(t *testing.T) {
	var out bytes.Buffer
	for _, args := range [][]string{{"volumes"}, {"cache", "shared"}} {
		if err := Prune(args, strings.NewReader(""), &out, &out); err == nil {
			t.Errorf("booth prune %v should be refused", args)
		}
	}
}
