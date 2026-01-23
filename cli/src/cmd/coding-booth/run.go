// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"

	"github.com/nawaman/codingbooth/src/pkg/booth"
	boothinit "github.com/nawaman/codingbooth/src/pkg/booth/init"
)

func runBooth(version string) {
	context := boothinit.InitializeAppContext(version, boothinit.DefaultInitializeAppContextBoundary{})

	if context.Verbose() {
		fmt.Printf("%+v\n", context)
	}

	runner := booth.NewBoothRunner(context)
	err := runner.Run()
	if err != nil {
		// For SilentExitError (from command mode), exit with the code silently
		if silentErr, ok := err.(*booth.SilentExitError); ok {
			os.Exit(silentErr.ExitCode)
			return
		}
		fmt.Println("❌ CodingBooth failed with error:", err)
		os.Exit(1)
		return
	}
	os.Exit(0)
}
