// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// PrepareBoothTmp creates and initializes .booth/.tmp/ with session metadata.
// This runs on the host before docker starts, so the directory is available
// inside the container via the bind mount.
func PrepareBoothTmp(ctx appctx.AppContext) appctx.AppContext {
	if ctx.Dryrun() {
		return ctx
	}

	codePath := ctx.Code()
	if codePath == "" {
		return ctx
	}

	boothDir := filepath.Join(codePath, ".booth")

	// Only create .booth/.tmp/ if .booth/ already exists.
	// We must not create .booth/ as a side effect — it would cause the booth
	// to mount an empty .booth/ directory on subsequent runs.
	if info, err := os.Stat(boothDir); err != nil || !info.IsDir() {
		return ctx
	}

	tmpDir := filepath.Join(boothDir, ".tmp")

	// Empty contents unless --keep-tmp-on-start is set
	if !ctx.KeepTmpOnStart() {
		if entries, err := os.ReadDir(tmpDir); err == nil {
			for _, entry := range entries {
				os.RemoveAll(filepath.Join(tmpDir, entry.Name()))
			}
		}
	}

	// Create .tmp/ directory if it doesn't exist
	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		return ctx
	}

	// Generate session ID
	sessionBytes := make([]byte, 6)
	if _, err := rand.Read(sessionBytes); err != nil {
		return ctx
	}
	sessionID := hex.EncodeToString(sessionBytes)

	// Write booth-startup.txt
	startupContent := fmt.Sprintf("started-at = %s\nsession-id = %s\n",
		time.Now().UTC().Format(time.RFC3339),
		sessionID,
	)
	startupFile := filepath.Join(tmpDir, "booth-startup.txt")
	os.WriteFile(startupFile, []byte(startupContent), 0644)

	return ctx
}

// cleanupBoothTmp empties .booth/.tmp/ on exit unless --leave-tmp-on-exit is set.
func cleanupBoothTmp(ctx appctx.AppContext) {
	if ctx.Dryrun() || ctx.LeaveTmpOnExit() {
		return
	}
	codePath := ctx.Code()
	if codePath == "" {
		return
	}
	tmpDir := filepath.Join(codePath, ".booth", ".tmp")
	entries, err := os.ReadDir(tmpDir)
	if err != nil {
		return
	}
	for _, entry := range entries {
		os.RemoveAll(filepath.Join(tmpDir, entry.Name()))
	}
}
