// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package workspace

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/ilist"
)

// ApplyEnvFile applies environment file configuration and returns updated AppContext.
func ApplyEnvFile(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	containerEnvFile := ctx.EnvFile()

	// If not set, default to <workspace>/.env when it exists
	if containerEnvFile == "" {
		candidate := filepath.Join(ctx.Workspace(), ".env")
		if fileExists(candidate) {
			containerEnvFile = candidate
			builder.Config.EnvFile = candidate
		}
	}

	// Respect the "not used" token
	if containerEnvFile != "" && containerEnvFile == "-" {
		if ctx.Verbose() {
			fmt.Println("Skipping --env-file (explicitly disabled).")
		}
		return builder.Build()
	}

	// If specified, it must exist; otherwise error out
	if containerEnvFile != "" {
		if !fileExists(containerEnvFile) {
			fmt.Fprintf(os.Stderr, "Error: env-file must be an existing file: %s\n", containerEnvFile)
			os.Exit(1)
		}

		builder.CommonArgs.Append(ilist.NewList[string]("--env-file", containerEnvFile))
		if ctx.Verbose() {
			fmt.Printf("Using env-file: %s\n", containerEnvFile)
		}
	}

	return builder.Build()
}

// fileExists checks if a file exists.
func fileExists(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !info.IsDir()
}
