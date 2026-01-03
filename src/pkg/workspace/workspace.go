// Package workspace provides the main Workspace type for managing Docker-based development environments.
package workspace

import (
	"fmt"
	"strings"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/docker"
)

type Workspace struct {
	ctx appctx.AppContext
}

// NewWorkspace creates a new Workspace with the given AppContext.
func NewWorkspace(ctx appctx.AppContext) *Workspace {
	return &Workspace{ctx: ctx}
}

// Run executes the workspace based on the provided run mode.
// The AppContext should already be prepared with all necessary arguments.
func (workspace *Workspace) Run(runMode string) error {
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
