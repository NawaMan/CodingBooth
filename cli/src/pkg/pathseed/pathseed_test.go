// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package pathseed

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
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

// Once the folder holds anything of its own it is the user's: a file deleted from it
// stays deleted.
func TestApply_LeavesAnExistingMarkedFolder(t *testing.T) {
	seed, target := t.TempDir(), t.TempDir()
	dir := "home/coder/.config/tool"
	write(t, filepath.Join(seed, dir, mountMarker), "")
	write(t, filepath.Join(seed, dir, "a.conf"), "a")
	write(t, filepath.Join(target, dir, mountMarker), "")
	write(t, filepath.Join(target, dir, "mine.conf"), "mine")

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

// A folder holding only the marker is what booth creates for a declared folder with no
// seed, so a seed added later fills it, as an empty file is filled.
func TestApply_FillsAFolderHoldingOnlyTheMarker(t *testing.T) {
	seed, target := t.TempDir(), t.TempDir()
	dir := "home/coder/.config/tool"
	write(t, filepath.Join(seed, dir, mountMarker), "")
	write(t, filepath.Join(seed, dir, "a.conf"), "a")
	write(t, filepath.Join(target, dir, mountMarker), "")

	seeded, err := Apply(seed, target)
	if err != nil {
		t.Fatal(err)
	}
	if got := read(t, filepath.Join(target, dir, "a.conf")); got != "a" {
		t.Errorf("a.conf = %q, want the seed", got)
	}
	if want := []string{filepath.FromSlash(dir)}; !reflect.DeepEqual(seeded, want) {
		t.Errorf("seeded = %v, want %v", seeded, want)
	}
}

// A ".mount-this" that is a folder is not booth's marker: the folder is the user's.
func TestApply_LeavesAFolderWhoseMarkerIsNotAFile(t *testing.T) {
	seed, target := t.TempDir(), t.TempDir()
	dir := "home/coder/.config/tool"
	write(t, filepath.Join(seed, dir, mountMarker), "")
	write(t, filepath.Join(seed, dir, "a.conf"), "a")
	if err := os.MkdirAll(filepath.Join(target, dir, mountMarker), 0755); err != nil {
		t.Fatal(err)
	}

	seeded, err := Apply(seed, target)
	if err != nil {
		t.Fatal(err)
	}
	if len(seeded) != 0 {
		t.Errorf("seeded = %v, want none", seeded)
	}
}

// Only declared paths are seeded, a file inside a declared folder included; the rest are
// reported as skipped, so a seed left by a deselected template creates no mount.
func TestApplyDeclared_SeedsOnlyDeclaredPaths(t *testing.T) {
	seed, target := t.TempDir(), t.TempDir()
	write(t, filepath.Join(seed, settings), "declared file")
	write(t, filepath.Join(seed, "home/coder/.tool/inside.conf"), "inside a declared folder")
	write(t, filepath.Join(seed, "home/coder/.chrome-data/Default", mountMarker), "")
	write(t, filepath.Join(seed, "home/coder/.chrome-data/Default/Bookmarks"), "left behind")
	write(t, filepath.Join(seed, "home/coder/.stray"), "left behind")

	seeded, skipped, err := ApplyDeclared(seed, target, []string{settings, "home/coder/.tool"})
	if err != nil {
		t.Fatal(err)
	}
	want := []string{filepath.FromSlash("home/coder/.config/tool/settings.json"), filepath.FromSlash("home/coder/.tool/inside.conf")}
	if !reflect.DeepEqual(sorted(seeded), sorted(want)) {
		t.Errorf("seeded = %v, want %v", seeded, want)
	}
	wantSkipped := []string{filepath.FromSlash("home/coder/.chrome-data/Default"), filepath.FromSlash("home/coder/.stray")}
	if !reflect.DeepEqual(sorted(skipped), sorted(wantSkipped)) {
		t.Errorf("skipped = %v, want %v", skipped, wantSkipped)
	}
	for _, p := range []string{"home/coder/.chrome-data", "home/coder/.stray"} {
		if _, err := os.Stat(filepath.Join(target, p)); !os.IsNotExist(err) {
			t.Errorf("%s was created from an undeclared seed", p)
		}
	}
}

// A declared path written as "./a//b/" names the same path as "a/b".
func TestApplyDeclared_CleansDeclaredPaths(t *testing.T) {
	for _, declared := range []string{"./home/coder/.tool/", "home//coder/./.tool", "/home/coder/.tool"} {
		seed, target := t.TempDir(), t.TempDir()
		write(t, filepath.Join(seed, "home/coder/.tool/a.conf"), "a")

		seeded, skipped, err := ApplyDeclared(seed, target, []string{declared})
		if err != nil {
			t.Fatal(err)
		}
		if len(seeded) != 1 || len(skipped) != 0 {
			t.Errorf("%q: seeded = %v, skipped = %v; want a.conf seeded", declared, seeded, skipped)
		}
	}
}

func sorted(list []string) []string {
	out := append([]string(nil), list...)
	sort.Strings(out)
	return out
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
