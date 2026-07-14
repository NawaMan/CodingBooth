// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeCacheTree materializes files (and .mount-this markers) under a fresh cache dir.
func writeCacheTree(t *testing.T, files ...string) string {
	t.Helper()
	cacheDir := t.TempDir()
	for _, f := range files {
		full := filepath.Join(cacheDir, filepath.FromSlash(f))
		if err := os.MkdirAll(filepath.Dir(full), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte("x"), 0644); err != nil {
			t.Fatal(err)
		}
	}
	return cacheDir
}

func containerPaths(mounts []cacheMount) []string {
	paths := make([]string, 0, len(mounts))
	for _, m := range mounts {
		paths = append(paths, m.containerPath)
	}
	return paths
}

func TestCollectCacheMounts_FilesAndMountThisDirs(t *testing.T) {
	cacheDir := writeCacheTree(t,
		"home/coder/.bash_history",         // plain file -> file mount
		"home/coder/.claude/.mount-this",   // marker    -> whole-dir mount
		"home/coder/.claude/settings.json", // inside the marked dir -> not mounted alone
		"home/coder/.claude/projects/notes.json",
	)

	mounts, protected := collectCacheMounts(cacheDir)
	if len(protected) != 0 {
		t.Fatalf("expected no protected paths, got %v", protected)
	}

	got := containerPaths(mounts)
	want := map[string]bool{
		"/home/coder/.bash_history": true,
		"/home/coder/.claude":       true,
	}
	if len(got) != len(want) {
		t.Fatalf("expected %d mounts, got %d: %v", len(want), len(got), got)
	}
	for _, p := range got {
		if !want[p] {
			t.Errorf("unexpected mount %q (the .mount-this dir should be mounted as a unit, "+
				"not descended into)", p)
		}
	}
}

// A cache entry landing on the project bind mount or on CodingBooth's own install must be
// reported, not silently dropped: a skipped entry looks to the user like a cache that simply
// does not work, with nothing to explain why.
func TestCollectCacheMounts_ProtectedPathsAreReportedNotMounted(t *testing.T) {
	cases := []struct {
		name string
		file string
		want string
	}{
		{"project dir, whole-dir mount", "home/coder/code/.mount-this", "/home/coder/code"},
		{"project dir, single file", "home/coder/code/main.go", "/home/coder/code/main.go"},
		{"codingbooth install", "opt/codingbooth/.mount-this", "/opt/codingbooth"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			cacheDir := writeCacheTree(t, tc.file)

			mounts, protected := collectCacheMounts(cacheDir)
			if len(mounts) != 0 {
				t.Errorf("protected path must not be mounted, got %v", containerPaths(mounts))
			}
			if len(protected) != 1 || protected[0] != tc.want {
				t.Fatalf("expected protected path %q, got %v", tc.want, protected)
			}
		})
	}
}

func TestCollectCacheMounts_ProtectedDoesNotBlockValidEntries(t *testing.T) {
	cacheDir := writeCacheTree(t,
		"home/coder/.bash_history",
		"opt/codingbooth/.mount-this",
	)

	mounts, protected := collectCacheMounts(cacheDir)
	if len(protected) != 1 {
		t.Fatalf("expected 1 protected path, got %v", protected)
	}
	// The valid entry is still collected; the caller decides to refuse to start.
	if got := containerPaths(mounts); len(got) != 1 || got[0] != "/home/coder/.bash_history" {
		t.Fatalf("expected the valid entry to still be collected, got %v", got)
	}
}

func TestProtectedCacheMountsError_NamesPathAndRemedy(t *testing.T) {
	err := protectedCacheMountsError([]string{"/home/coder/code"})
	msg := err.Error()
	for _, want := range []string{"/home/coder/code", ".booth/cache/home/coder/code", "Refusing to start"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error message should mention %q, got:\n%s", want, msg)
		}
	}
}
