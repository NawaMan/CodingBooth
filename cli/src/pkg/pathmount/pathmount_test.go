// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package pathmount

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func mkTree(t *testing.T, root string, dirs, files []string) {
	t.Helper()
	for _, d := range dirs {
		dir := filepath.Join(root, filepath.FromSlash(d))
		if err := os.MkdirAll(dir, 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, Marker), nil, 0644); err != nil {
			t.Fatal(err)
		}
	}
	for _, f := range files {
		path := filepath.Join(root, filepath.FromSlash(f))
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("x"), 0644); err != nil {
			t.Fatal(err)
		}
	}
}

func TestWalk(t *testing.T) {
	tree := t.TempDir()
	mkTree(t, tree,
		[]string{"home/coder/.gnupg", "opt/app"},
		[]string{"README.md", "home/coder/.bash_history", "home/coder/.gnupg/pubring.kbx", "opt/app/data/x"})

	got := Walk(tree)
	want := []Entry{
		{Rel: "home/coder/.bash_history"},
		{Rel: "home/coder/.gnupg", Dir: true}, // its contents are part of it
		{Rel: "opt/app", Dir: true},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Walk = %+v, want %+v (README.md at the top is never an item)", got, want)
	}
	if Walk(filepath.Join(tree, "missing")) != nil {
		t.Errorf("a missing tree has no items")
	}
}

func TestDeclared(t *testing.T) {
	booth := t.TempDir()
	config := `cache-files = ["home/coder/.bash_history", "/home/coder/.zsh_history"]
cache-dirs = ["home/coder/.gnupg:0700", "./home//coder/.n8n/"]
shared-dirs = ["home/coder/.config/helix"]
`
	if err := os.WriteFile(filepath.Join(booth, "config.toml"), []byte(config), 0644); err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{
		"home/coder/.bash_history": true, "home/coder/.zsh_history": true,
		"home/coder/.gnupg": true, "home/coder/.n8n": true,
	}
	if got := Declared(booth, "cache"); !reflect.DeepEqual(got, want) {
		t.Errorf("Declared(cache) = %v, want %v", got, want)
	}
	if got := Declared(booth, "shared"); !reflect.DeepEqual(got, map[string]bool{"home/coder/.config/helix": true}) {
		t.Errorf("Declared(shared) = %v", got)
	}
	if got := Declared(t.TempDir(), "cache"); got == nil || len(got) != 0 {
		t.Errorf("no config.toml declares nothing (and is not nil), got %v", got)
	}
}

func TestSplitKeepsDeclaredAndInside(t *testing.T) {
	declared := map[string]bool{"home/coder/.config": true, "home/coder/.bash_history": true}
	entries := []Entry{
		{Rel: "home/coder/.bash_history"},
		{Rel: "home/coder/.config/helix", Dir: true}, // inside a declared folder
		{Rel: "home/coder/.gnupg", Dir: true},
		{Rel: "home/coder/.bash_history_old"}, // a prefix in name only is not inside
	}
	kept, left := Split(entries, declared)
	if !reflect.DeepEqual(kept, entries[:2]) {
		t.Errorf("kept = %+v", kept)
	}
	if !reflect.DeepEqual(left, entries[2:]) {
		t.Errorf("left = %+v", left)
	}
}

func TestLeftoversAndNotice(t *testing.T) {
	booth := t.TempDir()
	mkTree(t, filepath.Join(booth, "cache"), []string{"home/coder/.gnupg", "home/coder/.local/share/folio"}, nil)
	if err := os.WriteFile(filepath.Join(booth, "config.toml"),
		[]byte(`cache-dirs = ["home/coder/.local/share/folio:0700"]`+"\n"), 0644); err != nil {
		t.Fatal(err)
	}
	left := Leftovers(booth, "cache")
	if !reflect.DeepEqual(left, []Entry{{Rel: "home/coder/.gnupg", Dir: true}}) {
		t.Fatalf("Leftovers = %+v", left)
	}
	notice := LeftoverNotice("cache", left)
	for _, want := range []string{".booth/cache/home/coder/.gnupg/", "booth prune cache", "--set cache-dirs="} {
		if !strings.Contains(notice, want) {
			t.Errorf("notice lacks %q:\n%s", want, notice)
		}
	}
	if LeftoverNotice("cache", nil) != "" {
		t.Errorf("no leftovers, no notice")
	}
}
