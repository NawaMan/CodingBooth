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

func TestProtectedPathMountsError_SharedKind(t *testing.T) {
	err := protectedPathMountsError("shared", []string{"/home/coder/code"})
	msg := err.Error()
	for _, want := range []string{"/home/coder/code", ".booth/shared/home/coder/code", "Refusing to start"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error message should mention %q, got:\n%s", want, msg)
		}
	}
}

func TestIsMountableContainerPath(t *testing.T) {
	cases := map[string]bool{
		"/home/coder/.chrome-data/Default/Bookmarks": true,
		"/opt/foo":     true,
		"/README.md":   false,
		"/shared-note": false,
		"/":            false,
	}
	for p, want := range cases {
		if got := isMountableContainerPath(p); got != want {
			t.Errorf("isMountableContainerPath(%q) = %v, want %v", p, got, want)
		}
	}
}

// A config.toml cache-dirs entry with a permission suffix is created with that
// mode at start; an existing dir is left alone; a bad suffix is skipped, not mounted
// under a path with a colon in it.
func TestEnsureCacheFromConfig_DirModeSuffix(t *testing.T) {
	boothDir := t.TempDir()
	config := "cache-dirs = [\"home/coder/.gnupg:0700\", \"home/coder/.bad:rwx\"]\n"
	if err := os.WriteFile(filepath.Join(boothDir, "config.toml"), []byte(config), 0644); err != nil {
		t.Fatal(err)
	}
	ensureCacheFromConfig(boothDir)

	gnupg := filepath.Join(boothDir, "cache", "home", "coder", ".gnupg")
	info, err := os.Stat(gnupg)
	if err != nil {
		t.Fatal(err)
	}
	if got := info.Mode().Perm(); got != 0o700 {
		t.Errorf(".gnupg mode = %o, want 700", got)
	}
	if _, err := os.Stat(filepath.Join(gnupg, ".mount-this")); err != nil {
		t.Errorf(".mount-this missing: %v", err)
	}
	entries, _ := os.ReadDir(filepath.Join(boothDir, "cache", "home", "coder"))
	for _, e := range entries {
		if strings.Contains(e.Name(), ":") || e.Name() == ".bad" {
			t.Errorf("bad entry should be skipped, found %q", e.Name())
		}
	}

	// A second start does not re-chmod a dir the user changed.
	if err := os.Chmod(gnupg, 0o750); err != nil {
		t.Fatal(err)
	}
	ensureCacheFromConfig(boothDir)
	info, _ = os.Stat(gnupg)
	if got := info.Mode().Perm(); got != 0o750 {
		t.Errorf("existing dir mode = %o, want it left at 750", got)
	}
}

// At start, a seed in .booth/shared-seed/ fills a declared Shared path before it would
// be created empty — on a fresh clone, and for an empty file a seed was added for later.
func TestSeedFrom_BeforeEnsure(t *testing.T) {
	boothDir := t.TempDir()
	rel := filepath.Join("home", "coder", ".config", "tool", "settings.json")
	config := "shared-files = [\"home/coder/.config/tool/settings.json\", \"home/coder/.other\"]\n"
	if err := os.WriteFile(filepath.Join(boothDir, "config.toml"), []byte(config), 0644); err != nil {
		t.Fatal(err)
	}
	seed := filepath.Join(boothDir, "shared-seed", rel)
	if err := os.MkdirAll(filepath.Dir(seed), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(seed, []byte(`{"team": true}`), 0644); err != nil {
		t.Fatal(err)
	}

	seedFrom(boothDir, "shared")
	ensureSharedFromConfig(boothDir)

	got, err := os.ReadFile(filepath.Join(boothDir, "shared", rel))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != `{"team": true}` {
		t.Errorf("settings.json = %q, want the seed", got)
	}
	other, err := os.ReadFile(filepath.Join(boothDir, "shared", "home", "coder", ".other"))
	if err != nil || len(other) != 0 {
		t.Errorf(".other = %q, %v; want an empty file", other, err)
	}
}
