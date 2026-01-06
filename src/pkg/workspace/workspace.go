// Package workspace provides the main Workspace type for managing Docker-based development environments.
package workspace

import (
	"fmt"
	"os"
	"strings"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/docker"
	"golang.org/x/term"
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
	flags := docker.DockerFlags{
		Dryrun:  workspace.ctx.Dryrun(),
		Verbose: workspace.ctx.Verbose(),
		Silent:  false,
	}

	ttyArgs := prepareTtyArgs()
	keepAliveArgs := prepareKeepAliveArgs(workspace.ctx.KeepAlive())
	userCmds := strings.Join(workspace.ctx.Cmds().Slice(), " ")

	args := make([]string, 0, 64)
	args = append(args, ttyArgs...)
	args = append(args, keepAliveArgs...)
	args = append(args, workspace.ctx.CommonArgs().Slice()...)
	args = append(args, workspace.ctx.RunArgs().Slice()...)
	args = append(args, "-e", "TZ="+workspace.ctx.Timezone())
	args = append(args, workspace.ctx.Image())
	args = append(args, "bash", "-lc", userCmds)

	// Execute the docker run command
	err := docker.Docker(flags, "run", args...)

	// Cleanup DinD resources if enabled
	if workspace.ctx.Dind() {
		flags.Silent = true
		dindName := getDindName(workspace.ctx)
		dindNet := getDindNet(workspace.ctx)
		_ = docker.Docker(flags, "stop", dindName)
		if workspace.ctx.CreatedDindNet() {
			_ = docker.Docker(flags, "network", "rm", dindNet)
		}
	}

	return err
}

// runAsDaemon executes a docker run command in daemon mode (background).
func (workspace *Workspace) runAsDaemon() error {
	flags := docker.DockerFlags{
		Dryrun:  workspace.ctx.Dryrun(),
		Verbose: workspace.ctx.Verbose(),
		Silent:  false,
	}

	keepAliveArgs := prepareKeepAliveArgs(workspace.ctx.KeepAlive())
	userCmds := make([]string, 0, 64)

	if workspace.ctx.Cmds().Length() > 0 {
		userCmds = append(userCmds, "bash", "-lc")
		userCmds = append(userCmds, workspace.ctx.Cmds().Slice()...)
	}

	fmt.Println("📦 Running workspace in daemon mode.")

	if workspace.ctx.KeepAlive() {
		fmt.Println("👉 Stop with Ctrl+C. The container will be kept (no --rm).")
	} else {
		fmt.Println("👉 Stop with Ctrl+C. The container will be removed (--rm) when stop.")
	}

	fmt.Printf("👉 Visit 'http://localhost:%d'\n", workspace.ctx.PortNumber()) // HostPort
	fmt.Printf("👉 To open an interactive shell instead: %s -- bash\n", workspace.ctx.ScriptName())
	fmt.Println("👉 To stop the running container:")
	fmt.Println()
	fmt.Printf("      docker stop %s\n", workspace.ctx.Name())
	fmt.Println()
	fmt.Printf("👉 Container Name: %s\n", workspace.ctx.Name())
	fmt.Print("👉 Container ID: ")

	if workspace.ctx.Dryrun() {
		fmt.Println("<--dryrun-->")
		fmt.Println()
	}

	args := make([]string, 0, 64)
	args = append(args, "-d")
	args = append(args, keepAliveArgs...)
	args = append(args, workspace.ctx.CommonArgs().Slice()...)
	args = append(args, workspace.ctx.RunArgs().Slice()...)
	args = append(args, "-e", "TZ="+workspace.ctx.Timezone())
	args = append(args, workspace.ctx.Image())
	args = append(args, userCmds...)

	// Execute the docker run command
	err := docker.Docker(flags, "run", args...)

	// If DinD is enabled in daemon mode, inform user how to stop it
	if workspace.ctx.Dind() {
		dindName := getDindName(workspace.ctx)
		dindNet := getDindNet(workspace.ctx)
		fmt.Printf("🔧 DinD sidecar running: %s (network: %s)\n", dindName, dindNet)
		fmt.Printf("   Stop with:  docker stop %s && docker network rm %s\n", dindName, dindNet)
	}

	return err
}

// runAsForeground executes a docker run command in foreground mode.
func (workspace *Workspace) runAsForeground() error {
	flags := docker.DockerFlags{
		Dryrun:  workspace.ctx.Dryrun(),
		Verbose: workspace.ctx.Verbose(),
		Silent:  false,
	}

	ttyArgs := prepareTtyArgs()
	keepAliveArgs := prepareKeepAliveArgs(workspace.ctx.KeepAlive())

	fmt.Println("📦 Running workspace in foreground.")
	fmt.Printf("👉 Visit 'http://localhost:%d'\n", workspace.ctx.PortNumber())
	if workspace.ctx.KeepAlive() {
		fmt.Println("👉 Stop with Ctrl+C. The container will be kept (no --rm).")
	} else {
		fmt.Println("👉 Stop with Ctrl+C. The container will be removed (--rm) when stop.")
	}
	fmt.Printf("👉 To open an interactive shell instead: '%s -- bash'\n", workspace.ctx.ScriptName())
	fmt.Println()

	args := make([]string, 0, 64)
	args = append(args, ttyArgs...)
	args = append(args, keepAliveArgs...)
	args = append(args, workspace.ctx.CommonArgs().Slice()...)
	args = append(args, workspace.ctx.RunArgs().Slice()...)
	args = append(args, "-e", "TZ="+workspace.ctx.Timezone())
	args = append(args, workspace.ctx.Image())

	// Execute the docker run command
	err := docker.Docker(flags, "run", args...)

	// Cleanup DinD resources if enabled
	if workspace.ctx.Dind() {
		dindName := getDindName(workspace.ctx)
		dindNet := getDindNet(workspace.ctx)
		flags.Silent = true
		_ = docker.Docker(flags, "stop", dindName)
		if workspace.ctx.CreatedDindNet() {
			_ = docker.Docker(flags, "network", "rm", dindNet)
		}
	}

	return err
}

func prepareTtyArgs() []string {
	if term.IsTerminal(int(os.Stdin.Fd())) && term.IsTerminal(int(os.Stdout.Fd())) {
		return []string{"-it"}
	}
	return []string{"-i"}
}

func prepareKeepAliveArgs(keepAlive bool) []string {
	if keepAlive {
		return nil
	}
	return []string{"--rm"}
}

func getDindName(ctx appctx.AppContext) string {
	return ctx.Name() + "-" + ctx.Port() + "-dind"
}

func getDindNet(ctx appctx.AppContext) string {
	return ctx.Name() + "-" + ctx.Port() + "-net"
}
