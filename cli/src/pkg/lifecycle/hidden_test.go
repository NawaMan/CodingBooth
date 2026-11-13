// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestHiddenSetAndKeysRoundTrip(t *testing.T) {
	dir := t.TempDir()
	code := filepath.Join(dir, "web")
	tree := filepath.Join(dir, "feature")
	for _, d := range []string{code, tree} {
		if err := os.Mkdir(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	h := Hidden{Path: filepath.Join(dir, "cache", "hidden.json")}
	if got := h.Keys(); len(got) != 0 {
		t.Fatalf("no file: keys = %v, want none", got)
	}
	if err := h.Set("web@docker", code, true); err != nil {
		t.Fatal(err)
	}
	if err := h.Set("worktree:"+tree, tree, true); err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{"web@docker": true, "worktree:" + tree: true}
	if got := h.Keys(); !reflect.DeepEqual(got, want) {
		t.Errorf("keys = %v, want %v", got, want)
	}

	if err := h.Set("web@docker", code, false); err != nil {
		t.Fatal(err)
	}
	want = map[string]bool{"worktree:" + tree: true}
	if got := h.Keys(); !reflect.DeepEqual(got, want) {
		t.Errorf("after unhide: keys = %v, want %v", got, want)
	}
}

func TestHiddenDropsEntriesWhoseFolderIsGone(t *testing.T) {
	dir := t.TempDir()
	tree := filepath.Join(dir, "feature")
	if err := os.Mkdir(tree, 0o755); err != nil {
		t.Fatal(err)
	}
	h := Hidden{Path: filepath.Join(dir, "hidden.json")}
	if err := h.Set("worktree:"+tree, tree, true); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(tree); err != nil {
		t.Fatal(err)
	}
	if got := h.Keys(); len(got) != 0 {
		t.Errorf("keys = %v, want none once the folder is gone", got)
	}
	if got := h.load(); len(got) != 0 {
		t.Errorf("file still holds %v; the gone entry should be dropped", got)
	}
}

func TestHiddenBrokenFileHidesNothing(t *testing.T) {
	path := filepath.Join(t.TempDir(), "hidden.json")
	if err := os.WriteFile(path, []byte("{not json"), 0o644); err != nil {
		t.Fatal(err)
	}
	if got := (Hidden{Path: path}).Keys(); len(got) != 0 {
		t.Errorf("keys = %v, want none", got)
	}
}
