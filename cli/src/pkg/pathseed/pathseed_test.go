// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package pathseed

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/nawaman/codingbooth/src/internal/hostskip"
)

func write(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, path string) string {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v", path, err)
	}
	return string(data)
}

const settings = "home/coder/.config/tool/settings.json"

func TestApply_SeedsAMissingFile(t *testing.T) {
	seed, target := t.TempDir(), t.TempDir()
	write(t, filepath.Join(seed, settings), `{"a": 1}`)

	seeded, err := Apply(seed, target)
	if err != nil {
		t.Fatal(err)
	}
	if got := read(t, filepath.Join(target, settings)); got != `{"a": 1}` {
		t.Errorf("target = %q, want the seed", got)
	}
	// Apply reports host-native paths — the caller turns them into "/" for the
	// message it prints (see seedFrom in booth.go).
	if want := []string{filepath.FromSlash(settings)}; !reflect.DeepEqual(seeded, want) {
		t.Errorf("seeded = %v, want %v", seeded, want)
	}
}

func TestApply_LeavesAFileWithContent(t *testing.T) {
	seed, target := t.TempDir(), t.TempDir()
	write(t, filepath.Join(seed, settings), `{"a": 1}`)
	write(t, filepath.Join(target, settings), `{"mine": true}`)

	seeded, err := Apply(seed, target)
	if err != nil {
		t.Fatal(err)
	}
	if got := read(t, filepath.Join(target, settings)); got != `{"mine": true}` {
		t.Errorf("target = %q, want it left as it was", got)
	}
	if len(seeded) != 0 {
		t.Errorf("seeded = %v, want none", seeded)
	}
}

// booth creates a declared path with no seed as an empty file; a seed added later must
// still fill it.
func TestApply_FillsAnEmptyFile(t *testing.T) {
	seed, target := t.TempDir(), t.TempDir()
	write(t, filepath.Join(seed, settings), `{"a": 1}`)
	write(t, filepath.Join(target, settings), "")

	if _, err := Apply(seed, target); err != nil {
		t.Fatal(err)
	}
	if got := read(t, filepath.Join(target, settings)); got != `{"a": 1}` {
		t.Errorf("target = %q, want the seed", got)
	}
}

func TestApply_CopiesAMarkedFolderWhole(t *testing.T) {
	seed, target := t.TempDir(), t.TempDir()
	dir := "home/coder/.config/tool"
	write(t, filepath.Join(seed, dir, mountMarker), "")
	write(t, filepath.Join(seed, dir, "a.conf"), "a")
	write(t, filepath.Join(seed, dir, "sub/b.conf"), "b")

	seeded, err := Apply(seed, target)
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{mountMarker, "a.conf", "sub/b.conf"} {
		if _, err := os.Stat(filepath.Join(target, dir, f)); err != nil {
			t.Errorf("%s not copied: %v", f, err)
		}
	}
	if want := []string{filepath.FromSlash(dir)}; !reflect.DeepEqual(seeded, want) {
		t.Errorf("seeded = %v, want %v", seeded, want)
	}
}

// Once the folder exists it is the user's: a file deleted from it stays deleted.
func TestApply_LeavesAnExistingMarkedFolder(t *testing.T) {
	seed, target := t.TempDir(), t.TempDir()
	dir := "home/coder/.config/tool"
	write(t, filepath.Join(seed, dir, mountMarker), "")
	write(t, filepath.Join(seed, dir, "a.conf"), "a")
	write(t, filepath.Join(target, dir, mountMarker), "")

	seeded, err := Apply(seed, target)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(target, dir, "a.conf")); !os.IsNotExist(err) {
		t.Errorf("a.conf should not be put back into an existing folder")
	}
	if len(seeded) != 0 {
		t.Errorf("seeded = %v, want none", seeded)
	}
}

func TestApply_SkipsFilesAtTheRoot(t *testing.T) {
	seed, target := t.TempDir(), t.TempDir()
	write(t, filepath.Join(seed, "README.md"), "docs")

	if _, err := Apply(seed, target); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(target, "README.md")); !os.IsNotExist(err) {
		t.Errorf("README.md at the seed root should not be copied")
	}
}

func TestApply_KeepsTheSeedsPermissions(t *testing.T) {
	hostskip.NoUnixModes(t)

	seed, target := t.TempDir(), t.TempDir()
	script := "home/coder/bin/hello"
	write(t, filepath.Join(seed, script), "#!/bin/sh\n")
	if err := os.Chmod(filepath.Join(seed, script), 0755); err != nil {
		t.Fatal(err)
	}

	if _, err := Apply(seed, target); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(filepath.Join(target, script))
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0755 {
		t.Errorf("mode = %v, want 0755", info.Mode().Perm())
	}
}

func TestApply_MissingSeedFolder(t *testing.T) {
	seeded, err := Apply(filepath.Join(t.TempDir(), "absent"), t.TempDir())
	if err != nil || seeded != nil {
		t.Errorf("Apply = %v, %v; want nil, nil", seeded, err)
	}
}
