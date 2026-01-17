// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package workspace provides the main Workspace type for managing Docker-based development environments.
package workspace

import (
	"fmt"
	"os"
	"strconv"
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
	userCmds := strings.Join(flattenArgs(workspace.ctx.Cmds()), " ")

	args := ilist.NewList[ilist.List[string]]()
	if len(ttyArgs) > 0 {
		args = args.ExtendByLists(ilist.NewListFromSlice([]ilist.List[string]{ilist.NewListFromSlice(ttyArgs)}))
	}
	if len(keepAliveArgs) > 0 {
		args = args.ExtendByLists(ilist.NewListFromSlice([]ilist.List[string]{ilist.NewListFromSlice(keepAliveArgs)}))
	}
	args = args.ExtendByLists(workspace.ctx.CommonArgs())
	args = args.ExtendByLists(workspace.ctx.RunArgs())
	args = args.ExtendByLists(
		ilist.NewListFromSlice([]ilist.List[string]{
			ilist.NewList("-e", "TZ="+workspace.ctx.Timezone()),
			ilist.NewList(workspace.ctx.Image()),
			ilist.NewList("bash", "-lc", userCmds),
		}),
	)

	// Execute the docker run command
	err := docker.Docker(flags, "run", args)

	// Cleanup DinD resources if enabled
	if workspace.ctx.Dind() {
		flags.Silent = true
		dindName := getDindName(workspace.ctx)
		dindNet := getDindNet(workspace.ctx)
		_ = docker.Docker(flags, "stop", ilist.NewList(ilist.NewList(dindName)))
		if workspace.ctx.CreatedDindNet() {
			_ = docker.Docker(flags, "network", ilist.NewList(ilist.NewList("rm", dindNet)))
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
		userCmds = append(userCmds, flattenArgs(workspace.ctx.Cmds())...)
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

	args := ilist.NewList[ilist.List[string]]()
	args = args.ExtendByLists(ilist.NewList(ilist.NewList("-d")))
	if len(keepAliveArgs) > 0 {
		args = args.ExtendByLists(ilist.NewList(ilist.NewListFromSlice(keepAliveArgs)))
	}

	args = args.ExtendByLists(workspace.ctx.CommonArgs())
	args = args.ExtendByLists(workspace.ctx.RunArgs())

	extraArgs := []ilist.List[string]{
		ilist.NewList("-e", "TZ="+workspace.ctx.Timezone()),
		ilist.NewList(workspace.ctx.Image()),
	}
	if len(userCmds) > 0 {
		extraArgs = append(extraArgs, ilist.NewListFromSlice(userCmds))
	}
	args = args.ExtendByLists(ilist.NewListFromSlice(extraArgs))

	// Execute the docker run command
	err := docker.Docker(flags, "run", args)

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
	if workspace.ctx.KeepAlive() {
		fmt.Println("👉 Stop with Ctrl+C. The container will be kept (no --rm).")
	} else {
		fmt.Println("👉 Stop with Ctrl+C. The container will be removed (--rm) when stop.")
	}
	fmt.Printf("👉 To open an interactive shell instead: '%s -- bash'\n", workspace.ctx.ScriptName())
	fmt.Println()

	args := ilist.NewList[ilist.List[string]]()
	if len(ttyArgs) > 0 {
		args = args.ExtendByLists(ilist.NewList(ilist.NewListFromSlice(ttyArgs)))
	}
	if len(keepAliveArgs) > 0 {
		args = args.ExtendByLists(ilist.NewList(ilist.NewListFromSlice(keepAliveArgs)))
	}

	args = args.ExtendByLists(workspace.ctx.CommonArgs())
	args = args.ExtendByLists(workspace.ctx.RunArgs())

	args = args.ExtendByLists(ilist.NewList(
		ilist.NewList("-e", "TZ="+workspace.ctx.Timezone()),
		ilist.NewList(workspace.ctx.Image()),
	))

	// Execute the docker run command
	err := docker.Docker(flags, "run", args)

	// Cleanup DinD resources if enabled
	if workspace.ctx.Dind() {
		dindName := getDindName(workspace.ctx)
		dindNet := getDindNet(workspace.ctx)
		flags.Silent = true
		_ = docker.Docker(flags, "stop", ilist.NewList(ilist.NewList(dindName)))
		if workspace.ctx.CreatedDindNet() {
			_ = docker.Docker(flags, "network", ilist.NewList(ilist.NewList("rm", dindNet)))
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
	return ctx.Name() + "-" + strconv.Itoa(ctx.PortNumber()) + "-dind"
}

func getDindNet(ctx appctx.AppContext) string {
	return ctx.Name() + "-" + strconv.Itoa(ctx.PortNumber()) + "-net"
}

// PrepareCommonArgs prepares common Docker run arguments and returns updated AppContext.
func PrepareCommonArgs(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	containerName := ctx.Name()
	if containerName == "" {
		containerName = ctx.ProjectName()
	}

	builder.CommonArgs.Append(ilist.NewList[string]("--name", containerName))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "HOST_UID="+ctx.HostUID()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "HOST_GID="+ctx.HostGID()))
	builder.CommonArgs.Append(ilist.NewList[string]("-v", ctx.Workspace()+":/home/coder/workspace"))
	builder.CommonArgs.Append(ilist.NewList[string]("-w", "/home/coder/workspace"))

	// Skip port mapping when using DinD (port is exposed on DinD container instead)
	if !ctx.Dind() {
		builder.CommonArgs.Append(ilist.NewList[string]("-p", fmt.Sprintf("%d:10000", ctx.PortNumber())))
	}

	// Metadata
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_SETUPS_DIR="+ctx.SetupsDir()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_CONTAINER_NAME="+ctx.Name()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("WS_DAEMON=%t", ctx.Daemon())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_HOST_PORT="+strconv.Itoa(ctx.PortNumber())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_IMAGE_NAME="+ctx.Image()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_RUNMODE="+ctx.RunMode()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_VARIANT_TAG="+ctx.Variant()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("WS_VERBOSE=%t", ctx.Verbose())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_VERSION_TAG="+ctx.Version()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_WORKSPACE_PATH="+ctx.Workspace()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_WORKSPACE_PORT=10000"))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("WS_HAS_NOTEBOOK=%t", ctx.HasNotebook())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("WS_HAS_VSCODE=%t", ctx.HasVscode())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("WS_HAS_DESKTOP=%t", ctx.HasDesktop())))

	// Additional metadata from AppContext
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_WS_VERSION="+ctx.WsVersion()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_CONFIG_FILE="+ctx.ConfigFile()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_SCRIPT_NAME="+ctx.ScriptName()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_SCRIPT_DIR="+ctx.ScriptDir()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_LIB_DIR="+ctx.LibDir()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("WS_KEEP_ALIVE=%t", ctx.KeepAlive())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("WS_SILENCE_BUILD=%t", ctx.SilenceBuild())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("WS_PULL=%t", ctx.Pull())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("WS_DIND=%t", ctx.Dind())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_DOCKERFILE="+ctx.Dockerfile()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_PROJECT_NAME="+ctx.ProjectName()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_TIMEZONE="+ctx.Timezone()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_PORT="+ctx.Port()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_ENV_FILE="+ctx.EnvFile()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_HOST_UID="+ctx.HostUID()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_HOST_GID="+ctx.HostGID()))

	// Custom startup script
	if ctx.Startup() != "" {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "WS_STARTUP="+ctx.Startup()))
	}

	if !ctx.Pull() {
		builder.CommonArgs.Append(ilist.NewList[string]("--pull=never"))
	}

	return builder.Build()
}

func flattenArgs(argsList ilist.List[ilist.List[string]]) []string {
	var flattened []string
	argsList.Range(func(_ int, group ilist.List[string]) bool {
		flattened = append(flattened, group.Slice()...)
		return true
	})
	return flattened
}
