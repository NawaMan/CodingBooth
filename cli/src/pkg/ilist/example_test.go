// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package ilist_test

import (
	"github.com/nawaman/coding-booth/src/pkg/ilist"
)

// Example demonstrates basic usage of the ilist package.
func Example() {
	// Create a mutable builder
	builder := ilist.NewAppendableList[string]()
	builder.Append("--name", "mycontainer")
	builder.Append("-v", "/host:/container")

	// Create immutable snapshot
	args := builder.Snapshot()

	// Further mutations don't affect the snapshot
	builder.Append("--rm")

	// Convert back to builder for modifications
	modified := args.ToBuilder()
	modified.Append("--network", "bridge")

	// Output shows the package works as expected
	_ = args
	_ = modified
}

// Example_dockerArgs demonstrates the docker args use case.
func Example_dockerArgs() {
	// Build common args
	commonArgs := ilist.NewAppendableList[string]()
	commonArgs.Append("--name", "workspace")
	commonArgs.Append("-v", "/workspace:/home/coder/workspace")

	// Create snapshot for reuse
	baseArgs := commonArgs.Snapshot()

	// Build run-specific args
	runArgs := baseArgs.ToBuilder()
	runArgs.Append("--network", "bridge")
	runArgs.Append("--rm")

	// Build daemon-specific args (from same base)
	daemonArgs := baseArgs.ToBuilder()
	daemonArgs.Append("-d")

	// Both variants have the base args but different additions
	_ = runArgs.Snapshot()
	_ = daemonArgs.Snapshot()
}
