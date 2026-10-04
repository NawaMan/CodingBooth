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

func TestAppleWrapperCopy(t *testing.T) {
	cache := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cache)
	project := t.TempDir()
	wrapper := filepath.Join(project, "booth")
	if err := os.WriteFile(wrapper, []byte("#!/bin/sh\necho wrapper\n"), 0o755); err != nil {
		t.Fatal(err)
	}

	got, err := appleWrapperCopy(project, wrapper)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.HasPrefix(got, filepath.Join(cache, "codingbooth", "apple-wrappers")+string(filepath.Separator)) || filepath.Base(got) != "booth" {
		t.Errorf("copy at %q, want <cache>/codingbooth/apple-wrappers/<project>/booth", got)
	}
	if strings.HasPrefix(got, project) {
		t.Errorf("copy %q must live outside the project, or Apple container drops the project mount", got)
	}
	data, err := os.ReadFile(got)
	if err != nil || string(data) != "#!/bin/sh\necho wrapper\n" {
		t.Errorf("copy content = %q, %v", data, err)
	}
	if info, _ := os.Stat(got); info == nil || info.Mode().Perm() != 0o755 {
		t.Errorf("copy must be executable, got %v", info)
	}

	// Refreshed on the next run, at the same place.
	if err := os.WriteFile(wrapper, []byte("v2"), 0o755); err != nil {
		t.Fatal(err)
	}
	again, _ := appleWrapperCopy(project, wrapper)
	if data, _ := os.ReadFile(again); again != got || string(data) != "v2" {
		t.Errorf("second run: %q with %q, want the same path refreshed", again, data)
	}

	// Another project gets its own copy.
	other := t.TempDir()
	if p, _ := appleWrapperCopy(other, wrapper); p == got {
		t.Errorf("two projects share the copy %q", p)
	}
}
