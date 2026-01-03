// Package workspace provides the main Workspace type for managing Docker-based development environments.
package workspace

import (
	"fmt"
	"os"
	"strings"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/docker"
	"github.com/nawaman/workspace/src/pkg/ilist"
	"golang.org/x/term"
)

type Workspace struct {
	ctx appctx.AppContext
}

// NewWorkspace creates a new Workspace with the given AppContext.
func NewWorkspace(ctx appctx.AppContext) *Workspace {
	return &Workspace{ctx: ctx}
}

// PrepareCommonArgs prepares common Docker run arguments and returns updated AppContext.
func PrepareCommonArgs(ctx appctx.AppContext, runMode string) appctx.AppContext {
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
	builder.AppendCommonArg("-e", "WS_RUNMODE="+runMode)
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

// Run executes the workspace based on the run mode determined from the context.
func (workspace *Workspace) Run() error {
	// Prepare arguments that don't depend on run mode
	ctx := workspace.ctx
	ctx = PrepareKeepAliveArgs(ctx)
	ctx = PrepareTtyArgs(ctx)

	// Determine run mode
	runMode := "COMMAND"
	if ctx.Daemon() {
		runMode = "DAEMON"
	} else if ctx.Cmds().Length() == 0 {
		runMode = "FOREGROUND"
	}

	// Prepare common args with run mode
	ctx = PrepareCommonArgs(ctx, runMode)

	// Update workspace context with prepared arguments
	workspace.ctx = ctx

	// Execute based on run mode
	switch runMode {
	case "DAEMON":
		return workspace.runAsDaemon()
	case "FOREGROUND":
		return workspace.runAsForeground()
	default:
		return workspace.runAsCommand()
	}
}

// runAsCommand executes a docker run command with user-specified commands in foreground mode.
func (workspace *Workspace) runAsCommand() error {
	userCmds := strings.Join(workspace.ctx.Cmds().Slice(), " ")
	args := make([]string, 0)
	args = append(args, workspace.ctx.TtyArgs().Slice()...)
	args = append(args, workspace.ctx.KeepAliveArgs().Slice()...)
	args = append(args, workspace.ctx.CommonArgs().Slice()...)
	args = append(args, workspace.ctx.RunArgs().Slice()...)
	args = append(args, "-e", "TZ="+workspace.ctx.Timezone())
	args = append(args, workspace.ctx.ImageName())
	args = append(args, "bash", "-lc", userCmds)

	// Execute the docker run command
	err := docker.Docker(workspace.ctx, "run", args...)

	// Cleanup DinD resources if enabled
	if workspace.ctx.Dind() {
		_ = docker.Docker(workspace.ctx, "stop", workspace.ctx.DindName())
		if workspace.ctx.CreatedDindNet() {
			_ = docker.Docker(workspace.ctx, "network", "rm", workspace.ctx.DindNet())
		}
	}

	return err
}

// runAsDaemon executes a docker run command in daemon mode (background).
func (workspace *Workspace) runAsDaemon() error {
	// Build user commands if any are provided
	userCmds := make([]string, 0)
	if workspace.ctx.Cmds().Length() > 0 {
		userCmds = append(userCmds, "bash", "-lc")
		userCmds = append(userCmds, workspace.ctx.Cmds().Slice()...)
	}

	fmt.Println("📦 Running workspace in daemon mode.")

	if !workspace.ctx.Keepalive() {
		fmt.Printf("👉 Stop with '%s -- exit'. The container will be removed (--rm) when stop.\n", workspace.ctx.ScriptName())
	}

	fmt.Printf("👉 Visit 'http://localhost:%s'\n", workspace.ctx.HostPort())
	fmt.Printf("👉 To open an interactive shell instead: %s -- bash\n", workspace.ctx.ScriptName())
	fmt.Println("👉 To stop the running container:")
	fmt.Println()
	fmt.Printf("      docker stop %s\n", workspace.ctx.ContainerName())
	fmt.Println()
	fmt.Printf("👉 Container Name: %s\n", workspace.ctx.ContainerName())
	fmt.Print("👉 Container ID: ")

	if workspace.ctx.Dryrun() {
		fmt.Println("<--dryrun-->")
		fmt.Println()
	}

	args := make([]string, 0)
	args = append(args, "-d")
	args = append(args, workspace.ctx.KeepAliveArgs().Slice()...)
	args = append(args, workspace.ctx.CommonArgs().Slice()...)
	args = append(args, workspace.ctx.RunArgs().Slice()...)
	args = append(args, "-e", "TZ="+workspace.ctx.Timezone())
	args = append(args, workspace.ctx.ImageName())
	args = append(args, userCmds...)

	// Execute the docker run command
	err := docker.Docker(workspace.ctx, "run", args...)

	// If DinD is enabled in daemon mode, inform user how to stop it
	if workspace.ctx.Dind() {
		fmt.Printf("🔧 DinD sidecar running: %s (network: %s)\n", workspace.ctx.DindName(), workspace.ctx.DindNet())
		fmt.Printf("   Stop with:  docker stop %s && docker network rm %s\n", workspace.ctx.DindName(), workspace.ctx.DindNet())
	}

	return err
}

// runAsForeground executes a docker run command in foreground mode.
func (workspace *Workspace) runAsForeground() error {
	fmt.Println("📦 Running workspace in foreground.")
	fmt.Println("👉 Stop with Ctrl+C. The container will be removed (--rm) when stop.")
	fmt.Printf("👉 To open an interactive shell instead: '%s -- bash'\n", workspace.ctx.ScriptName())
	fmt.Println()

	args := make([]string, 0)
	args = append(args, workspace.ctx.TtyArgs().Slice()...)
	args = append(args, workspace.ctx.KeepAliveArgs().Slice()...)
	args = append(args, workspace.ctx.CommonArgs().Slice()...)
	args = append(args, workspace.ctx.RunArgs().Slice()...)
	args = append(args, "-e", "TZ="+workspace.ctx.Timezone())
	args = append(args, workspace.ctx.ImageName())

	// Execute the docker run command
	err := docker.Docker(workspace.ctx, "run", args...)

	// Cleanup DinD resources if enabled
	if workspace.ctx.Dind() {
		_ = docker.Docker(workspace.ctx, "stop", workspace.ctx.DindName())
		if workspace.ctx.CreatedDindNet() {
			_ = docker.Docker(workspace.ctx, "network", "rm", workspace.ctx.DindNet())
		}
	}

	return err
}
