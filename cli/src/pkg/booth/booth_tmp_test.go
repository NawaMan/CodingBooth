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
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

func buildTmpCtx(codePath string, dryrun, keepTmpOnStart, leaveTmpOnExit bool) appctx.AppContext {
	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Code = nillable.NewNillableString(codePath)
	builder.Config.Dryrun = nillable.NewNillableBool(dryrun)
	builder.Config.KeepTmpOnStart = keepTmpOnStart
	builder.Config.LeaveTmpOnExit = leaveTmpOnExit
	return builder.Build()
}

func TestPrepareBoothTmp_CreatesTmpDir(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	os.MkdirAll(boothDir, 0755)

	ctx := buildTmpCtx(tmpDir, false, false, false)
	PrepareBoothTmp(ctx)

	tmpPath := filepath.Join(boothDir, ".tmp")
	if _, err := os.Stat(tmpPath); err != nil {
		t.Errorf("Expected .booth/.tmp/ to be created, got error: %v", err)
	}
}

func TestPrepareBoothTmp_WritesStartupFile(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	os.MkdirAll(boothDir, 0755)

	ctx := buildTmpCtx(tmpDir, false, false, false)
	PrepareBoothTmp(ctx)

	startupFile := filepath.Join(boothDir, ".tmp", "booth-startup.txt")
	data, err := os.ReadFile(startupFile)
	if err != nil {
		t.Fatalf("Expected booth-startup.txt to be written, got error: %v", err)
	}

	content := string(data)
	if !strings.Contains(content, "started-at = ") {
		t.Errorf("Expected started-at in booth-startup.txt, got: %s", content)
	}
	if !strings.Contains(content, "session-id = ") {
		t.Errorf("Expected session-id in booth-startup.txt, got: %s", content)
	}
}

func TestPrepareBoothTmp_SessionIDIsHex12Chars(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	os.MkdirAll(boothDir, 0755)

	ctx := buildTmpCtx(tmpDir, false, false, false)
	PrepareBoothTmp(ctx)

	data, _ := os.ReadFile(filepath.Join(boothDir, ".tmp", "booth-startup.txt"))
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "session-id = ") {
			sessionID := strings.TrimPrefix(line, "session-id = ")
			if len(sessionID) != 12 {
				t.Errorf("Expected session-id of 12 hex chars, got %d chars: %q", len(sessionID), sessionID)
			}
			return
		}
	}
	t.Error("session-id not found in booth-startup.txt")
}

func TestPrepareBoothTmp_UniqueSessionIDs(t *testing.T) {
	ids := make(map[string]bool)
	for i := 0; i < 100; i++ {
		tmpDir := t.TempDir()
		boothDir := filepath.Join(tmpDir, ".booth")
		os.MkdirAll(boothDir, 0755)

		ctx := buildTmpCtx(tmpDir, false, false, false)
		PrepareBoothTmp(ctx)

		data, _ := os.ReadFile(filepath.Join(boothDir, ".tmp", "booth-startup.txt"))
		for _, line := range strings.Split(string(data), "\n") {
			if strings.HasPrefix(line, "session-id = ") {
				id := strings.TrimPrefix(line, "session-id = ")
				if ids[id] {
					t.Errorf("Duplicate session-id: %s", id)
				}
				ids[id] = true
			}
		}
	}
}

func TestPrepareBoothTmp_CleansExistingFiles(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	tmpPath := filepath.Join(boothDir, ".tmp")
	os.MkdirAll(tmpPath, 0755)

	// Create a pre-existing file
	os.WriteFile(filepath.Join(tmpPath, "old-file.txt"), []byte("old"), 0644)

	ctx := buildTmpCtx(tmpDir, false, false, false)
	PrepareBoothTmp(ctx)

	// Old file should be gone
	if _, err := os.Stat(filepath.Join(tmpPath, "old-file.txt")); err == nil {
		t.Error("Expected old-file.txt to be cleaned, but it still exists")
	}

	// But booth-startup.txt should be written
	if _, err := os.Stat(filepath.Join(tmpPath, "booth-startup.txt")); err != nil {
		t.Error("Expected booth-startup.txt to exist after cleanup")
	}
}

func TestPrepareBoothTmp_KeepTmpOnStart(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	tmpPath := filepath.Join(boothDir, ".tmp")
	os.MkdirAll(tmpPath, 0755)

	// Create a pre-existing file
	os.WriteFile(filepath.Join(tmpPath, "keep-me.txt"), []byte("keep"), 0644)

	ctx := buildTmpCtx(tmpDir, false, true, false)
	PrepareBoothTmp(ctx)

	// Old file should still exist
	if _, err := os.Stat(filepath.Join(tmpPath, "keep-me.txt")); err != nil {
		t.Error("Expected keep-me.txt to be preserved with --keep-tmp-on-start")
	}
}

func TestPrepareBoothTmp_DryrunDoesNothing(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	os.MkdirAll(boothDir, 0755)

	ctx := buildTmpCtx(tmpDir, true, false, false)
	PrepareBoothTmp(ctx)

	tmpPath := filepath.Join(boothDir, ".tmp")
	if _, err := os.Stat(tmpPath); err == nil {
		t.Error("Expected .booth/.tmp/ to NOT be created in dryrun mode")
	}
}

func TestPrepareBoothTmp_NoBoothDir(t *testing.T) {
	tmpDir := t.TempDir()
	// Don't create .booth/ directory

	ctx := buildTmpCtx(tmpDir, false, false, false)
	PrepareBoothTmp(ctx) // Should not panic or create .booth/

	if _, err := os.Stat(filepath.Join(tmpDir, ".booth")); err == nil {
		t.Error("Expected .booth/ to NOT be created as a side effect")
	}
}

func TestPrepareBoothTmp_EmptyCodePath(t *testing.T) {
	ctx := buildTmpCtx("", false, false, false)
	PrepareBoothTmp(ctx) // Should not panic
}

func TestCleanupBoothTmp_RemovesFiles(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	tmpPath := filepath.Join(boothDir, ".tmp")
	os.MkdirAll(tmpPath, 0755)

	os.WriteFile(filepath.Join(tmpPath, "some-file.txt"), []byte("data"), 0644)
	os.MkdirAll(filepath.Join(tmpPath, "subdir"), 0755)
	os.WriteFile(filepath.Join(tmpPath, "subdir", "nested.txt"), []byte("nested"), 0644)

	ctx := buildTmpCtx(tmpDir, false, false, false)
	cleanupBoothTmp(ctx)

	entries, _ := os.ReadDir(tmpPath)
	if len(entries) != 0 {
		t.Errorf("Expected .booth/.tmp/ to be empty after cleanup, got %d entries", len(entries))
	}

	// Directory itself should still exist
	if _, err := os.Stat(tmpPath); err != nil {
		t.Error("Expected .booth/.tmp/ directory to still exist after cleanup")
	}
}

func TestCleanupBoothTmp_LeaveTmpOnExit(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	tmpPath := filepath.Join(boothDir, ".tmp")
	os.MkdirAll(tmpPath, 0755)

	os.WriteFile(filepath.Join(tmpPath, "preserve-me.txt"), []byte("data"), 0644)

	ctx := buildTmpCtx(tmpDir, false, false, true)
	cleanupBoothTmp(ctx)

	if _, err := os.Stat(filepath.Join(tmpPath, "preserve-me.txt")); err != nil {
		t.Error("Expected preserve-me.txt to remain with --leave-tmp-on-exit")
	}
}

func TestCleanupBoothTmp_DryrunDoesNothing(t *testing.T) {
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	tmpPath := filepath.Join(boothDir, ".tmp")
	os.MkdirAll(tmpPath, 0755)

	os.WriteFile(filepath.Join(tmpPath, "survive.txt"), []byte("data"), 0644)

	ctx := buildTmpCtx(tmpDir, true, false, false)
	cleanupBoothTmp(ctx)

	if _, err := os.Stat(filepath.Join(tmpPath, "survive.txt")); err != nil {
		t.Error("Expected survive.txt to remain in dryrun mode")
	}
}
