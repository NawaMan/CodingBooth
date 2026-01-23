// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package booth provides the main Booth type for managing Docker-based development environments.
package booth

import (
	"fmt"
	"os"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// BoothRunner handles the "run" command for booth operations.
// It orchestrates the preparation of AppContext and execution of the booth.
type BoothRunner struct {
	ctx appctx.AppContext
}

// NewBoothRunner creates a new BoothRunner with the given AppContext.
func NewBoothRunner(ctx appctx.AppContext) *BoothRunner {
	return &BoothRunner{ctx: ctx}
}

// Run is the main entry point that prepares the context and executes the booth.
func (runner *BoothRunner) Run() error {
	// Prepare arguments and determine run mode (matching booth order)
	ctx := runner.ctx
	ctx = ValidateVariant(ctx)
	ctx = EnsureDockerImage(ctx)
	ctx = ApplyEnvFile(ctx)
	ctx = PortDetermination(ctx)
	ctx = ShowDebugBanner(ctx)
	ctx = SetupDind(ctx)
	ctx = PrepareRunMode(ctx)
	ctx = PrepareCommonArgs(ctx)

	// Create booth with prepared context and run
	booth := NewBooth(ctx)
	return booth.Run(ctx.RunMode())
}

// PrepareRunMode determines the run mode and stores it in the context.
func PrepareRunMode(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	if ctx.Daemon() {
		builder.RunMode = "DAEMON"
	} else if ctx.Cmds().Length() == 0 {
		builder.RunMode = "FOREGROUND"
	} else {
		builder.RunMode = "COMMAND"
	}

	return builder.Build()
}

// SetupDind sets up Docker-in-Docker if enabled and returns updated AppContext.
func SetupDind(ctx appctx.AppContext) appctx.AppContext {
	// Early return if DinD is not enabled
	if !ctx.Dind() {
		return ctx
	}

	builder := ctx.ToBuilder()

	// Clean up any leftover containers/networks from previous booth runs
	// This prevents port conflicts when restarting the booth
	cleanupPreviousBoothInstances(ctx, ctx.ProjectName())

	// Set up unique network and sidecar names
	dindNet := getDindNet(ctx)
	dindName := getDindName(ctx)

	// Create network if it doesn't exist
	createdNet := createDindNetwork(ctx, dindNet)
	builder.CreatedDindNet = createdNet

	// Extract extra port mappings from RunArgs before stripping
	extraPorts := extractPortFlags(ctx.RunArgs())

	// Start DinD sidecar if not already running (pass hostPort for port mapping)
	err := startDindSidecar(ctx, dindName, dindNet, ctx.PortNumber(), extraPorts)
	if err != nil {
		fmt.Fprintf(os.Stderr, "❌ Failed to start DinD sidecar.\n\n")

		// Try to diagnose if this is a port conflict
		port, diagnostic := diagnosePortConflict(err, ctx.PortNumber(), extraPorts)
		if port != "" {
			fmt.Fprintf(os.Stderr, "   %s\n", diagnostic)
		} else {
			// Generic error - show the original error message
			fmt.Fprintf(os.Stderr, "   Error: %v\n", err)
			fmt.Fprintf(os.Stderr, "   Check if any port is already in use.\n")
			fmt.Fprintf(os.Stderr, "   Use 'lsof -i :<port>' or 'ss -tlnp | grep <port>' to find the process.\n")
		}
		os.Exit(1)
	}

	// Wait for DinD to become ready
	waitForDindReady(ctx, dindName, dindNet)

	// Strip network and port flags from RUN_ARGS (not allowed with container network mode)
	builder.RunArgs = stripNetworkAndPortFlags(ctx.RunArgs())

	// Use container network mode to share DinD's network namespace
	// This allows localhost access to DinD's ports from the booth
	builder.CommonArgs.Append(ilist.NewList[string]("--network", fmt.Sprintf("container:%s", dindName)))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "DOCKER_HOST=tcp://localhost:2375"))

	return builder.Build()
}
