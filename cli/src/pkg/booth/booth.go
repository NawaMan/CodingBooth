// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package booth provides the main Booth type for managing Docker-based development environments.
package booth

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"golang.org/x/term"
)

type Booth struct {
	ctx appctx.AppContext
}

// SilentExitError signals that the program should exit with a specific code without printing an error message.
// This is used for command mode when the user's command fails - we forward the exit code silently.
type SilentExitError struct {
	ExitCode int
}

func (e *SilentExitError) Error() string {
	return fmt.Sprintf("exit code %d", e.ExitCode)
}

// NewBooth creates a new Booth with the given AppContext.
func NewBooth(ctx appctx.AppContext) *Booth {
	return &Booth{ctx: ctx}
}

// Run executes the booth based on the provided run mode.
// The AppContext should already be prepared with all necessary arguments.
func (booth *Booth) Run(runMode string) error {
	// Execute based on run mode
	switch runMode {
	case "DAEMON":
		return booth.runAsDaemon()
	case "FOREGROUND":
		return booth.runAsForeground()
	default:
		return booth.runAsCommand()
	}
}

// runAsCommand executes a docker run command with user-specified commands in foreground mode.
func (booth *Booth) runAsCommand() error {
	flags := docker.DockerFlags{
		Dryrun:  booth.ctx.Dryrun(),
		Verbose: booth.ctx.Verbose(),
		Silent:  false,
	}

	ttyArgs := prepareTtyArgs()
	keepAliveArgs := prepareKeepAliveArgs(booth.ctx.KeepAlive())
	userCmds := strings.Join(flattenArgs(booth.ctx.Cmds()), " ")

	args := ilist.NewList[ilist.List[string]]()
	if len(ttyArgs) > 0 {
		args = args.ExtendByLists(ilist.NewListFromSlice([]ilist.List[string]{ilist.NewListFromSlice(ttyArgs)}))
	}
	if len(keepAliveArgs) > 0 {
		args = args.ExtendByLists(ilist.NewListFromSlice([]ilist.List[string]{ilist.NewListFromSlice(keepAliveArgs)}))
	}
	args = args.ExtendByLists(booth.ctx.CommonArgs())
	args = args.ExtendByLists(booth.ctx.RunArgs())
	args = args.ExtendByLists(
		ilist.NewListFromSlice([]ilist.List[string]{
			ilist.NewList("-e", "TZ="+booth.ctx.Timezone()),
			ilist.NewList(booth.ctx.Image()),
			ilist.NewList("bash", "-lc", userCmds),
		}),
	)

	// Execute the docker run command
	err := docker.Docker(flags, "run", args)

	// Cleanup sandbox/DinD sidecars after command exits.
	cleanupFlags := flags
	cleanupFlags.Silent = true
	cleanupSandboxResources(booth.ctx, &cleanupFlags)
	if booth.ctx.Dind() {
		dindName := getDindName(booth.ctx)
		dindNet := getDindNet(booth.ctx)
		_ = docker.Docker(cleanupFlags, "stop", ilist.NewList(ilist.NewList(dindName)))
		if booth.ctx.CreatedDindNet() {
			_ = docker.Docker(cleanupFlags, "network", ilist.NewList(ilist.NewList("rm", dindNet)))
		}
	}

	// In command mode, forward exit codes silently (no error message)
	if exitErr, ok := err.(*docker.DockerExitError); ok {
		return &SilentExitError{ExitCode: exitErr.ExitCode}
	}

	return err
}

// runAsDaemon executes a docker run command in daemon mode (background).
func (booth *Booth) runAsDaemon() error {
	flags := docker.DockerFlags{
		Dryrun:  booth.ctx.Dryrun(),
		Verbose: booth.ctx.Verbose(),
		Silent:  false,
	}

	keepAliveArgs := prepareKeepAliveArgs(booth.ctx.KeepAlive())
	userCmds := make([]string, 0, 64)

	if booth.ctx.Cmds().Length() > 0 {
		userCmds = append(userCmds, "bash", "-lc")
		userCmds = append(userCmds, flattenArgs(booth.ctx.Cmds())...)
	}

	fmt.Println("📦 Running booth in daemon mode.")

	if booth.ctx.KeepAlive() {
		fmt.Println("👉 Stop with Ctrl+C. The container will be kept (no --rm).")
	} else {
		fmt.Println("👉 Stop with Ctrl+C. The container will be removed (--rm) when stop.")
	}

	fmt.Printf("👉 Visit 'http://localhost:%d'\n", booth.ctx.PortNumber()) // HostPort
	fmt.Printf("👉 To open an interactive shell instead: %s -- bash\n", booth.ctx.ScriptName())
	fmt.Println("👉 To stop the running container:")
	fmt.Println()
	fmt.Printf("      docker stop %s\n", booth.ctx.Name())
	fmt.Println()
	fmt.Printf("👉 Container Name: %s\n", booth.ctx.Name())
	fmt.Print("👉 Container ID: ")

	if booth.ctx.Dryrun() {
		fmt.Println("<--dryrun-->")
		fmt.Println()
	}

	args := ilist.NewList[ilist.List[string]]()
	args = args.ExtendByLists(ilist.NewList(ilist.NewList("-d")))
	if len(keepAliveArgs) > 0 {
		args = args.ExtendByLists(ilist.NewList(ilist.NewListFromSlice(keepAliveArgs)))
	}

	args = args.ExtendByLists(booth.ctx.CommonArgs())
	args = args.ExtendByLists(booth.ctx.RunArgs())

	extraArgs := []ilist.List[string]{
		ilist.NewList("-e", "TZ="+booth.ctx.Timezone()),
		ilist.NewList(booth.ctx.Image()),
	}
	if len(userCmds) > 0 {
		extraArgs = append(extraArgs, ilist.NewListFromSlice(userCmds))
	}
	args = args.ExtendByLists(ilist.NewListFromSlice(extraArgs))

	// Execute the docker run command
	err := docker.Docker(flags, "run", args)

	// If DinD is enabled in daemon mode, inform user how to stop it
	if booth.ctx.Sandbox() {
		fmt.Printf("🛡️  Sandbox sidecar running: %s\n", getSandboxProxyName(booth.ctx))
		if booth.ctx.Dind() {
			fmt.Printf("   Reusing DinD netns owner: %s\n", getDindName(booth.ctx))
		} else {
			fmt.Printf("   Netns owner sidecar: %s (network: %s)\n", getSandboxNetnsName(booth.ctx), getSandboxNet(booth.ctx))
		}
	}

	if booth.ctx.Dind() {
		dindName := getDindName(booth.ctx)
		dindNet := getDindNet(booth.ctx)
		fmt.Printf("🔧 DinD sidecar running: %s (network: %s)\n", dindName, dindNet)
		fmt.Printf("   Stop with:  docker stop %s && docker network rm %s\n", dindName, dindNet)
	}

	return err
}

// runAsForeground executes a docker run command in foreground mode.
func (booth *Booth) runAsForeground() error {
	flags := docker.DockerFlags{
		Dryrun:  booth.ctx.Dryrun(),
		Verbose: booth.ctx.Verbose(),
		Silent:  false,
	}

	ttyArgs := prepareTtyArgs()
	keepAliveArgs := prepareKeepAliveArgs(booth.ctx.KeepAlive())

	fmt.Println("📦 Running booth in foreground.")
	if booth.ctx.KeepAlive() {
		fmt.Println("👉 Stop with Ctrl+C. The container will be kept (no --rm).")
	} else {
		fmt.Println("👉 Stop with Ctrl+C. The container will be removed (--rm) when stop.")
	}
	fmt.Printf("👉 To open an interactive shell instead: '%s -- bash'\n", booth.ctx.ScriptName())
	fmt.Println()

	args := ilist.NewList[ilist.List[string]]()
	if len(ttyArgs) > 0 {
		args = args.ExtendByLists(ilist.NewList(ilist.NewListFromSlice(ttyArgs)))
	}
	if len(keepAliveArgs) > 0 {
		args = args.ExtendByLists(ilist.NewList(ilist.NewListFromSlice(keepAliveArgs)))
	}

	args = args.ExtendByLists(booth.ctx.CommonArgs())
	args = args.ExtendByLists(booth.ctx.RunArgs())

	args = args.ExtendByLists(ilist.NewList(
		ilist.NewList("-e", "TZ="+booth.ctx.Timezone()),
		ilist.NewList(booth.ctx.Image()),
	))

	// Execute the docker run command
	err := docker.Docker(flags, "run", args)

	// Cleanup sandbox/DinD sidecars after foreground exits.
	cleanupFlags := flags
	cleanupFlags.Silent = true
	cleanupSandboxResources(booth.ctx, &cleanupFlags)
	if booth.ctx.Dind() {
		dindName := getDindName(booth.ctx)
		dindNet := getDindNet(booth.ctx)
		_ = docker.Docker(cleanupFlags, "stop", ilist.NewList(ilist.NewList(dindName)))
		if booth.ctx.CreatedDindNet() {
			_ = docker.Docker(cleanupFlags, "network", ilist.NewList(ilist.NewList("rm", dindNet)))
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
	codePath := normalizeCodePath(ctx.Code())
	createdAt := time.Now().UTC().Format(time.RFC3339)
	builder.CommonArgs.Append(ilist.NewList[string]("-v", codePath+":/home/coder/code"))
	builder.CommonArgs.Append(ilist.NewList[string]("-w", "/home/coder/code"))

	if ctx.Sandbox() {
		addReadOnlyProjectFile(builder, codePath, ".booth/config.toml")
		addReadOnlyProjectFile(builder, codePath, ".booth/Boothfile")
		addReadOnlyEgressAllowlist(builder, codePath, ctx.SandboxAllowlistFile())
	}

	// Lifecycle management labels used by list/start/stop/restart/remove commands.
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.managed=true"))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.project="+ctx.ProjectName()))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.variant="+ctx.Variant()))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.code-path="+codePath))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.created-at="+createdAt))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.version="+ctx.CbVersion()))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", fmt.Sprintf("cb.keep-alive=%t", ctx.KeepAlive())))

	// Skip port mapping when using shared network namespace sidecars.
	if !ctx.Dind() && !ctx.Sandbox() {
		builder.CommonArgs.Append(ilist.NewList[string]("-p", fmt.Sprintf("%d:10000", ctx.PortNumber())))
	}

	// Metadata
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_SETUPS="+ctx.SetupsDir()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_CONTAINER_NAME="+ctx.Name()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_DAEMON=%t", ctx.Daemon())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_HOST_PORT="+strconv.Itoa(ctx.PortNumber())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_IMAGE_NAME="+ctx.Image()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_RUNMODE="+ctx.RunMode()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_VARIANT_TAG="+ctx.Variant()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_VERBOSE=%t", ctx.Verbose())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_VERSION_TAG="+ctx.Version()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_CODE_PATH="+codePath))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_CODE_PORT=10000"))

	// Additional metadata from AppContext
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_VERSION="+ctx.CbVersion()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_CONFIG_FILE="+ctx.ConfigFile()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_SCRIPT_NAME="+ctx.ScriptName()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_SCRIPT_DIR="+ctx.ScriptDir()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_LIB_DIR="+ctx.LibDir()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_KEEP_ALIVE=%t", ctx.KeepAlive())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_SILENCE_BUILD=%t", ctx.SilenceBuild())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_PULL=%t", ctx.Pull())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_DIND=%t", ctx.Dind())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_SANDBOX=%t", ctx.Sandbox())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_DOCKERFILE="+ctx.Dockerfile()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_PROJECT_NAME="+ctx.ProjectName()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_TIMEZONE="+ctx.Timezone()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_PORT="+ctx.Port()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_ENV_FILE="+ctx.EnvFile()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_HOST_UID="+ctx.HostUID()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_HOST_GID="+ctx.HostGID()))

	// Custom startup script
	if ctx.Startup() != "" {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_STARTUP="+ctx.Startup()))
	}

	if !ctx.Pull() {
		builder.CommonArgs.Append(ilist.NewList[string]("--pull=never"))
	}

	return builder.Build()
}

func normalizeCodePath(path string) string {
	if path == "" {
		return path
	}
	absPath, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	return absPath
}

func addReadOnlyProjectFile(builder *appctx.AppContextBuilder, codePath, relPath string) {
	if codePath == "" || relPath == "" {
		return
	}
	hostPath := filepath.Join(codePath, relPath)
	info, err := os.Stat(hostPath)
	if err != nil || info.IsDir() {
		return
	}
	containerPath := filepath.Join("/home/coder/code", relPath)
	builder.CommonArgs.Append(ilist.NewList[string]("-v", hostPath+":"+containerPath+":ro"))
}

func addReadOnlyEgressAllowlist(builder *appctx.AppContextBuilder, codePath, allowlistPath string) {
	if codePath == "" || allowlistPath == "" {
		return
	}

	var rel string
	if filepath.IsAbs(allowlistPath) {
		if relPath, err := filepath.Rel(codePath, allowlistPath); err == nil && !strings.HasPrefix(relPath, ".."+string(filepath.Separator)) && relPath != ".." {
			rel = relPath
		} else {
			return
		}
	} else {
		rel = allowlistPath
	}

	addReadOnlyProjectFile(builder, codePath, rel)
}

func flattenArgs(argsList ilist.List[ilist.List[string]]) []string {
	var flattened []string
	argsList.Range(func(_ int, group ilist.List[string]) bool {
		flattened = append(flattened, group.Slice()...)
		return true
	})
	return flattened
}
