// Package workspace provides the main Workspace type for managing Docker-based development environments.
package workspace

import (
	"fmt"
	"os"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/ilist"
	"golang.org/x/term"
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
	// Prepare arguments and determine run mode (matching workspace.sh order)
	ctx := runner.ctx
	ctx = SetupDind(ctx)
	ctx = PrepareRunMode(ctx)
	ctx = PrepareCommonArgs(ctx)
	ctx = PrepareKeepAliveArgs(ctx)
	ctx = PrepareTtyArgs(ctx)

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

// PrepareCommonArgs prepares common Docker run arguments and returns updated AppContext.
func PrepareCommonArgs(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	builder.AppendCommonArg("--name", ctx.ContainerName())
	builder.AppendCommonArg("-e", "HOST_UID="+ctx.HostUID())
	builder.AppendCommonArg("-e", "HOST_GID="+ctx.HostGID())
	builder.AppendCommonArg("-v", ctx.WorkspacePath()+":/home/coder/workspace")
	builder.AppendCommonArg("-w", "/home/coder/workspace")
	builder.AppendCommonArg("-p", ctx.HostPort()+":10000")

	// Metadata
	builder.AppendCommonArg("-e", "WS_SETUPS_DIR="+ctx.SetupsDir())
	builder.AppendCommonArg("-e", "WS_CONTAINER_NAME="+ctx.ContainerName())
	builder.AppendCommonArg("-e", fmt.Sprintf("WS_DAEMON=%t", ctx.Daemon()))
	builder.AppendCommonArg("-e", "WS_HOST_PORT="+ctx.HostPort())
	builder.AppendCommonArg("-e", "WS_IMAGE_NAME="+ctx.ImageName())
	builder.AppendCommonArg("-e", "WS_RUNMODE="+ctx.RunMode())
	builder.AppendCommonArg("-e", "WS_VARIANT_TAG="+ctx.Variant())
	builder.AppendCommonArg("-e", fmt.Sprintf("WS_VERBOSE=%t", ctx.Verbose()))
	builder.AppendCommonArg("-e", "WS_VERSION_TAG="+ctx.Version())
	builder.AppendCommonArg("-e", "WS_WORKSPACE_PATH="+ctx.WorkspacePath())
	builder.AppendCommonArg("-e", "WS_WORKSPACE_PORT="+ctx.WorkspacePort())
	builder.AppendCommonArg("-e", fmt.Sprintf("WS_HAS_NOTEBOOK=%t", ctx.HasNotebook()))
	builder.AppendCommonArg("-e", fmt.Sprintf("WS_HAS_VSCODE=%t", ctx.HasVscode()))
	builder.AppendCommonArg("-e", fmt.Sprintf("WS_HAS_DESKTOP=%t", ctx.HasDesktop()))

	if !ctx.DoPull() {
		builder.AppendCommonArg("--pull=never")
	}

	return builder.Build()
}

// PrepareKeepAliveArgs prepares keep-alive arguments and returns updated AppContext.
func PrepareKeepAliveArgs(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	builder.KeepaliveArgs = ilist.NewAppendableList[string]()
	if !ctx.Keepalive() {
		builder.KeepaliveArgs.Append("--rm")
	}

	return builder.Build()
}

// PrepareTtyArgs prepares TTY arguments and returns updated AppContext.
func PrepareTtyArgs(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	builder.TtyArgs = ilist.NewAppendableList[string]()

	// Default: interactive only
	builder.TtyArgs.Append("-i")

	// If both stdin (fd 0) and stdout (fd 1) are terminals, use interactive + TTY
	if term.IsTerminal(int(os.Stdin.Fd())) && term.IsTerminal(int(os.Stdout.Fd())) {
		builder.TtyArgs = ilist.NewAppendableList[string]()
		builder.TtyArgs.Append("-it")
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
	dindNet := fmt.Sprintf("%s-%s-net", ctx.ContainerName(), ctx.HostPort())
	dindName := fmt.Sprintf("%s-%s-dind", ctx.ContainerName(), ctx.HostPort())
	builder.DindNet = dindNet
	builder.DindName = dindName

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
	builder.AppendCommonArg("--network", dindNet)
	builder.AppendCommonArg("-e", fmt.Sprintf("DOCKER_HOST=tcp://%s:2375", dindName))

	return builder.Build()
}
