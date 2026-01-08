// Package workspace provides the main Workspace type for managing Docker-based development environments.
package workspace

import (
	"fmt"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/ilist"
)

// WorkspaceRunner handles the "run" command for workspace operations.
// It orchestrates the preparation of AppContext and execution of the workspace.
type WorkspaceRunner struct {
	ctx appctx.AppContext
}

// NewWorkspaceRunner creates a new WorkspaceRunner with the given AppContext.
func NewWorkspaceRunner(ctx appctx.AppContext) *WorkspaceRunner {
	return &WorkspaceRunner{ctx: ctx}
}

// Run is the main entry point that prepares the context and executes the workspace.
func (runner *WorkspaceRunner) Run() error {
	// Prepare arguments and determine run mode (matching workspace order)
	ctx := runner.ctx
	ctx = ValidateVariant(ctx)
	ctx = EnsureDockerImage(ctx)
	ctx = ApplyEnvFile(ctx)
	ctx = PortDetermination(ctx)
	ctx = ShowDebugBanner(ctx)
	ctx = SetupDind(ctx)
	ctx = PrepareRunMode(ctx)
	ctx = PrepareCommonArgs(ctx)

	// Create workspace with prepared context and run
	workspace := NewWorkspace(ctx)
	return workspace.Run(ctx.RunMode())
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

	// Start DinD sidecar if not already running
	startDindSidecar(ctx, dindName, dindNet)

	// Wait for DinD to become ready
	waitForDindReady(ctx, dindName, dindNet)

	// Strip network flags from RUN_ARGS
	builder.RunArgs = stripNetworkFlags(ctx.RunArgs())

	// Add DinD network and DOCKER_HOST to COMMON_ARGS
	builder.CommonArgs.Append(ilist.NewList[string]("--network", dindNet))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("DOCKER_HOST=tcp://%s:2375", dindName)))

	return builder.Build()
}
