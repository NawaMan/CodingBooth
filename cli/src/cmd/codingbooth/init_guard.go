// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	boothinit "github.com/nawaman/codingbooth/src/pkg/booth/init"
)

// initOrExit calls boothinit.InitializeAppContext and converts any panic raised
// during argument / env / TOML parsing into a friendly stderr message plus an
// exit status of 2 (matching the Go runtime's own panic exit code, so wrappers
// and CI that already branched on it keep working).
//
// The init package uses panic(error) for user-input failures (e.g. "--idle-time
// requires a positive integer"). Without this guard the CLI prints the full Go
// stack trace for what is really a usage error.
func initOrExit(version string, boundary boothinit.InitializeAppContextBoundary) (ctx appctx.AppContext) {
	defer func() {
		if r := recover(); r != nil {
			fmt.Fprintf(os.Stderr, "❌ %v\n", r)
			os.Exit(2)
		}
	}()
	ctx = boothinit.InitializeAppContext(version, boundary)
	return
}
