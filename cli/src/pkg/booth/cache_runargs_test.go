// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func runArgsOf(groups ...[]string) *ilist.AppendableList[ilist.List[string]] {
	list := ilist.NewAppendableList[ilist.List[string]]()
	for _, g := range groups {
		list.Append(ilist.NewListFromSlice(g))
	}
	return list
}

func TestRunArgVolumeTargets(t *testing.T) {
	existing := t.TempDir()
	missing := filepath.Join(t.TempDir(), "absent")

	got := runArgVolumeTargets(runArgsOf(
		[]string{"-e", "FOO=bar"},
		[]string{"-v", existing + ":/home/coder/.cargo/registry"},
		[]string{"--volume", missing + ":/home/coder/.npm:ro"},
		[]string{"-v", "named_vol:/var/lib/data"},
		[]string{"-v", missing + ":/home/coder/.cargo/git:create"},
		[]string{"-v", missing + ":/home/coder/.m2:ro,create"},
	))

	if !got["/home/coder/.cargo/registry"] {
		t.Errorf("an existing host path should count as mounted: %v", got)
	}
	if got["/home/coder/.npm"] {
		t.Errorf("a missing host path is dropped later, so it must not count: %v", got)
	}
	if !got["/var/lib/data"] {
		t.Errorf("a named volume should count as mounted: %v", got)
	}
	if !got["/home/coder/.cargo/git"] || !got["/home/coder/.m2"] {
		t.Errorf("a missing host path with `create` is created later, so it must count: %v", got)
	}
	if len(runArgVolumeTargets(nil)) != 0 {
		t.Errorf("nil run-args should mount nothing")
	}
}

// Every way Docker takes a mount counts, and a target is compared after cleaning:
// --mount, -v=/--volume= inline values, and a trailing slash.
func TestRunArgVolumeTargets_MountFormsAndCleanTargets(t *testing.T) {
	existing := t.TempDir()
	missing := filepath.Join(t.TempDir(), "absent")

	got := runArgVolumeTargets(runArgsOf(
		[]string{"--mount", "type=bind,src=" + existing + ",dst=/home/coder/.m2"},
		[]string{"--mount=type=volume,source=vol,target=/var/lib/pg"},
		[]string{"--mount", "type=bind,source=" + missing + ",destination=/home/coder/.gradle"},
		[]string{"-v=" + existing + ":/home/coder/.npm/"},
		[]string{"--volume=named:/opt/data//cache"},
		[]string{"--volume-driver=local"},
	))

	for _, want := range []string{"/home/coder/.m2", "/var/lib/pg", "/home/coder/.gradle", "/home/coder/.npm", "/opt/data/cache"} {
		if !got[want] {
			t.Errorf("expected %s to count as mounted: %v", want, got)
		}
	}
	if len(got) != 5 {
		t.Errorf("--volume-driver is not a mount; got %v", got)
	}
}

// A cache entry on a path run-args already mount must step aside: Docker refuses a
// duplicate mount point, so keeping both stops the booth from starting. This is the
// rust registry-cache (auto) + cargo-cache (host mount) pair.
func TestAddCacheAndSharedMounts_CacheStepsAsideForRunArgMount(t *testing.T) {
	project := t.TempDir()
	spec := t.TempDir()
	for _, d := range []string{"cache/home/coder/.cargo/registry", "cache/home/coder/.cargo/git"} {
		dir := filepath.Join(spec, filepath.FromSlash(d))
		if err := os.MkdirAll(dir, 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, ".mount-this"), nil, 0644); err != nil {
			t.Fatal(err)
		}
	}
	hostRegistry := t.TempDir()

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    runArgsOf([]string{"-v", hostRegistry + ":/home/coder/.cargo/registry"}),
		BoothDir:   spec,
	}
	// Folder entries only, so no image is inspected for booth--file-sync.
	addCacheAndSharedMounts(builder, project, "docker", "")

	var targets []string
	builder.CommonArgs.Snapshot().Range(func(_ int, group ilist.List[string]) bool {
		if group.Length() == 2 && group.At(0) == "-v" {
			targets = append(targets, volumeTarget(group.At(1)))
		}
		return true
	})
	joined := strings.Join(targets, " ")
	if strings.Contains(joined, "/home/coder/.cargo/registry") {
		t.Errorf("cache mounted ~/.cargo/registry although run-args mount it: %s", joined)
	}
	if !strings.Contains(joined, "/home/coder/.cargo/git") {
		t.Errorf("the other cache entry should still mount: %s", joined)
	}
}

// The same pair on a fresh host: rust+cargo-cache's host folder does not exist yet, but
// its `create` option makes it later, so the cache entry must still step aside.
func TestAddCacheAndSharedMounts_CacheStepsAsideForCreateMount(t *testing.T) {
	project := t.TempDir()
	spec := t.TempDir()
	dir := filepath.Join(spec, "cache", "home", "coder", ".cargo", "registry")
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".mount-this"), nil, 0644); err != nil {
		t.Fatal(err)
	}
	notYet := filepath.Join(t.TempDir(), "registry")

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    runArgsOf([]string{"-v", notYet + ":/home/coder/.cargo/registry:create"}),
		BoothDir:   spec,
	}
	addCacheAndSharedMounts(builder, project, "docker", "")

	builder.CommonArgs.Snapshot().Range(func(_ int, group ilist.List[string]) bool {
		if group.Length() == 2 && group.At(0) == "-v" && volumeTarget(group.At(1)) == "/home/coder/.cargo/registry" {
			t.Errorf("cache mounted ~/.cargo/registry although a `create` run-arg mounts it: %s", group.At(1))
		}
		return true
	})
}

// Through addCacheAndSharedMounts, Shared mounts any path (it once kept only home/,
// opt/, … and dropped srv/ in silence), and a file at the top of either tree is left
// out with a notice instead of landing at /README.md.
func TestAddCacheAndSharedMounts_AnySharedPathAndTopLevelNotice(t *testing.T) {
	spec := t.TempDir()
	for _, d := range []string{"shared/srv/app", "cache/data"} {
		dir := filepath.Join(spec, filepath.FromSlash(d))
		if err := os.MkdirAll(dir, 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, ".mount-this"), nil, 0644); err != nil {
			t.Fatal(err)
		}
	}
	for _, f := range []string{"shared/README.md", "cache/README.md"} {
		if err := os.WriteFile(filepath.Join(spec, filepath.FromSlash(f)), []byte("doc"), 0644); err != nil {
			t.Fatal(err)
		}
	}

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		BoothDir:   spec,
	}
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	orig := os.Stderr
	os.Stderr = w
	// Folder entries only, so no image is inspected for booth--file-sync.
	addCacheAndSharedMounts(builder, t.TempDir(), "docker", "")
	os.Stderr = orig
	w.Close()
	notices, _ := io.ReadAll(r)

	var targets []string
	builder.CommonArgs.Snapshot().Range(func(_ int, group ilist.List[string]) bool {
		if group.Length() == 2 && group.At(0) == "-v" {
			targets = append(targets, volumeTarget(group.At(1)))
		}
		return true
	})
	joined := strings.Join(targets, " ")
	for _, want := range []string{"/srv/app", "/data"} {
		if !strings.Contains(joined, want) {
			t.Errorf("expected %s to mount, got %s", want, joined)
		}
	}
	if strings.Contains(joined, "/README.md") {
		t.Errorf("a top-level file must not mount: %s", joined)
	}
	for _, want := range []string{".booth/shared/README.md", ".booth/cache/README.md"} {
		if !strings.Contains(string(notices), want) {
			t.Errorf("expected a notice naming %s, got %q", want, notices)
		}
	}
}
