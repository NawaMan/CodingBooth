// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

func listBooths(_ string) {
	handleLifecycleErr(lifecycle.List(os.Args[2:], os.Stdout, os.Stderr))
}

func startBooth(_ string) {
	handleLifecycleErr(lifecycle.Start(os.Args[2:], os.Stderr))
}

func stopBooth(_ string) {
	handleLifecycleErr(lifecycle.Stop(os.Args[2:], os.Stderr))
}

func restartBooth(_ string) {
	handleLifecycleErr(lifecycle.Restart(os.Args[2:], os.Stderr))
}

func removeBooth(_ string) {
	handleLifecycleErr(lifecycle.Remove(os.Args[2:], os.Stderr))
}

func pruneBooths(_ string) {
	handleLifecycleErr(lifecycle.Prune(os.Args[2:], os.Stdin, os.Stdout, os.Stderr))
}

func handleLifecycleErr(err error) {
	if err == nil {
		return
	}
	if err.Error() != "" {
		fmt.Fprintln(os.Stderr, err)
	}
	os.Exit(lifecycle.ExitCode(err))
}
