// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
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
	if len(runArgVolumeTargets(nil)) != 0 {
		t.Errorf("nil run-args should mount nothing")
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
