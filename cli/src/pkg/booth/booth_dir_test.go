// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

func TestAddReadOnlyBoothDir_MountsTheExplicitDir(t *testing.T) {
	project := t.TempDir()
	projectBooth := filepath.Join(project, ".booth")
	if err := os.MkdirAll(projectBooth, 0755); err != nil {
		t.Fatal(err)
	}
	spec := t.TempDir()

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BoothDir:   spec,
	}
	addReadOnlyBoothDir(builder, project)

	want := spec + ":/home/coder/code/.booth:ro"
	found := false
	builder.CommonArgs.Snapshot().Range(func(_ int, group ilist.List[string]) bool {
		if group.Length() == 2 && group.At(0) == "-v" {
			if group.At(1) == projectBooth+":/home/coder/code/.booth:ro" {
				t.Fatalf("mounted the project .booth: %s", group.At(1))
			}
			if group.At(1) == want {
				found = true
			}
		}
		return true
	})
	if !found {
		t.Fatalf("expected mount %s", want)
	}
}

func TestNormalizeDockerFile_ExplicitBoothDirSkipsProjectBoothfile(t *testing.T) {
	project := t.TempDir()
	projectBooth := filepath.Join(project, ".booth")
	if err := os.MkdirAll(projectBooth, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(projectBooth, "Boothfile"), []byte("# project boothfile\n"), 0644); err != nil {
		t.Fatal(err)
	}
	spec := t.TempDir()

	builder := &appctx.AppContextBuilder{BoothDir: spec}
	builder.Config.Code = nillable.NewNillableString(project)

	got := NormalizeDockerFile(builder.Build())
	if got != "" {
		t.Fatalf("NormalizeDockerFile() = %q, want empty when the spec has no Boothfile", got)
	}
}
