// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package pathmode

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/nawaman/codingbooth/src/internal/hostskip"
)

func TestSplit(t *testing.T) {
	cases := []struct {
		entry string
		path  string
		mode  os.FileMode
	}{
		{"home/coder/.gnupg", "home/coder/.gnupg", 0},
		{"home/coder/.gnupg:0700", "home/coder/.gnupg", 0o700},
		{"home/coder/.gnupg:700", "home/coder/.gnupg", 0o700},
		{"home/coder/.cache:0750", "home/coder/.cache", 0o750},
	}
	for _, c := range cases {
		path, mode, err := Split(c.entry)
		if err != nil {
			t.Errorf("Split(%q) error: %v", c.entry, err)
			continue
		}
		if path != c.path || mode != c.mode {
			t.Errorf("Split(%q) = (%q, %o), want (%q, %o)", c.entry, path, mode, c.path, c.mode)
		}
	}
}

func TestSplitRejectsBadMode(t *testing.T) {
	for _, entry := range []string{
		"home/coder/.gnupg:",
		"home/coder/.gnupg:rwx",
		"home/coder/.gnupg:0800",
		"home/coder/.gnupg:07",
		"home/coder/.gnupg:01777",
		"home/coder/.gnupg:0000",
	} {
		if _, _, err := Split(entry); err == nil {
			t.Errorf("Split(%q) should fail", entry)
		}
	}
}

func TestPathFallsBackToEntry(t *testing.T) {
	if got := Path("a/b:0700"); got != "a/b" {
		t.Errorf("Path = %q, want a/b", got)
	}
	if got := Path("a/b:bad"); got != "a/b:bad" {
		t.Errorf("Path = %q, want the entry back", got)
	}
}

func TestMkdirAllSetsModeOnCreate(t *testing.T) {
	hostskip.NoUnixModes(t)

	dir := filepath.Join(t.TempDir(), "home", "coder", ".gnupg")
	if err := MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(dir)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != 0o700 {
		t.Errorf("mode = %o, want 700", got)
	}
	// Parents keep the default.
	parent, _ := os.Stat(filepath.Dir(dir))
	if parent.Mode().Perm() == 0o700 {
		t.Errorf("parent should not get the leaf's mode")
	}
}

func TestMkdirAllLeavesExistingDirAlone(t *testing.T) {
	hostskip.NoUnixModes(t)

	dir := filepath.Join(t.TempDir(), ".gnupg")
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := MkdirAll(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	info, _ := os.Stat(dir)
	if got := info.Mode().Perm(); got != 0o755 {
		t.Errorf("existing dir mode = %o, want it left at 755", got)
	}
}
