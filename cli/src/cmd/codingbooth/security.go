// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/booth"
	boothinit "github.com/nawaman/codingbooth/src/pkg/booth/init"
)

// printSecurityWarning prints the security warning a `booth run` with the same options would show,
// without building, starting, or asking anything. Exit 1 when there is a warning, 0 when there is
// none — so a script (or a hosted launcher) can check a booth before it starts one.
func printSecurityWarning(version string) {
	args := append([]string{os.Args[0]}, os.Args[2:]...)
	context := initOrExit(version, runBoundary{
		DefaultInitializeAppContextBoundary: boothinit.DefaultInitializeAppContextBoundary{},
		args:                                args,
	})

	warning, found := booth.SecurityWarning(context)
	if !found {
		fmt.Println("No security warning.")
		return
	}
	fmt.Print(strings.TrimPrefix(warning, "\n"))
	os.Exit(1)
}
