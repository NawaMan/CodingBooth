// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package booth provides the main Booth type for managing Docker-based development environments.
package booth

import (
	"fmt"

	"github.com/nawaman/coding-booth/src/pkg/appctx"
	"github.com/nawaman/coding-booth/src/pkg/ilist"
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

	// Set up unique network and sidecar names
	dindNet := getDindNet(ctx)
	dindName := getDindName(ctx)

	// Create network if it doesn't exist
	createdNet := createDindNetwork(ctx, dindNet)
	builder.CreatedDindNet = createdNet

	// Start DinD sidecar if not already running (pass hostPort for port mapping)
	startDindSidecar(ctx, dindName, dindNet, ctx.PortNumber())

	// Wait for DinD to become ready
	waitForDindReady(ctx, dindName, dindNet)

	// Strip network and port flags from RUN_ARGS (not allowed with container network mode)
	builder.RunArgs = stripNetworkAndPortFlags(ctx.RunArgs())

	// Use container network mode to share DinD's network namespace
	// This allows localhost access to DinD's ports from the workspace
	builder.CommonArgs.Append(ilist.NewList[string]("--network", fmt.Sprintf("container:%s", dindName)))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "DOCKER_HOST=tcp://localhost:2375"))

	return builder.Build()
}
