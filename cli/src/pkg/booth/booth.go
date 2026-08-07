// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package booth provides the main Booth type for managing Docker-based development environments.
package booth

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/BurntSushi/toml"
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

// RestartRequestedError signals that the user requested a restart from inside the container.
// The host binary should re-run the full pipeline (re-reading config, rebuilding if needed).
type RestartRequestedError struct{}

func (e *RestartRequestedError) Error() string {
	return "restart requested"
}

// NewBooth creates a new Booth with the given AppContext.
func NewBooth(ctx appctx.AppContext) *Booth {
	return &Booth{ctx: ctx}
}

// Run executes the booth based on the provided run mode.
// The AppContext should already be prepared with all necessary arguments.
func (booth *Booth) Run(runMode string) error {
	// Hand the port back to the OS: the container is about to publish it, and
	// docker cannot bind a port this process is still holding. Every path below
	// ends in a `docker run` that maps it. Sidecars that publish the port earlier
	// (DinD, egress) release it themselves.
	//
	// The on-disk claim outlives the listener on purpose — it is what keeps another
	// booth off this port while docker works its way to the bind — and is dropped
	// once the run returns and the container owns the port for real.
	releasePortReservation()
	defer releasePortClaim()

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

	// Start TCP tunnel watcher (watches .booth/.tmp/tcp-tunnels/ for booth--expose)
	tunnelCtx, tunnelCancel := context.WithCancel(context.Background())
	if !booth.ctx.Dryrun() {
		containerName := booth.ctx.Name()
		if containerName == "" {
			containerName = booth.ctx.ProjectName()
		}
		go StartTcpTunnelWatcher(tunnelCtx, booth.ctx, containerName)
	}

	// Execute the docker run command
	LogTimef(os.Stderr, "Info: running container...\n")
	err := docker.Docker(flags, "run", args)
	LogTimef(os.Stderr, "Info: container exited.\n")

	// Stop tunnel watcher
	tunnelCancel()

	// Check for restart/idle markers before cleanup removes them
	restartRequested := checkAndCleanRestartMarker(booth.ctx)
	idleShutdown := checkAndCleanIdleShutdownMarker(booth.ctx)

	// Cleanup .booth/.tmp/ on exit (unless --leave-tmp-on-exit)
	cleanupBoothTmp(booth.ctx)

	// Cleanup egress/DinD sidecars after command exits.
	cleanupFlags := flags
	cleanupFlags.Silent = true
	cleanupFlags.Verbose = false
	cleanupEgressResources(booth.ctx, &cleanupFlags)
	if booth.ctx.Dind() {
		dindName := getDindName(booth.ctx)
		dindNet := getDindNet(booth.ctx)
		_ = docker.Docker(cleanupFlags, "stop", ilist.NewList(ilist.NewList(dindName)))
		if booth.ctx.CreatedDindNet() {
			_ = docker.Docker(cleanupFlags, "network", ilist.NewList(ilist.NewList("rm", dindNet)))
		}
	}

	if restartRequested {
		return &RestartRequestedError{}
	}

	if idleShutdown {
		return &IdleShutdownError{ExitCode: booth.ctx.IdleExitCode()}
	}

	printHomeVolumeWarning(booth.ctx)

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

	LogPrintln("📦 Running booth in daemon mode.")

	if booth.ctx.KeepAlive() {
		LogPrintln("👉 Stop with Ctrl+C. The container will be kept (no --rm).")
	} else {
		LogPrintln("👉 Stop with Ctrl+C. The container will be removed (--rm) when stop.")
	}

	if booth.ctx.Public() {
		LogPrintf("👉 Visit 'https://localhost:%d'\n", booth.ctx.PortNumber())
	} else {
		LogPrintf("👉 Visit 'http://localhost:%d'\n", booth.ctx.PortNumber())
	}
	LogPrintf("👉 To open an interactive shell instead: %s -- bash\n", booth.ctx.ScriptName())
	LogPrintln("👉 To stop the running container:")
	fmt.Println()
	fmt.Printf("      docker stop %s\n", booth.ctx.Name())
	fmt.Println()
	LogPrintf("👉 Container Name: %s\n", booth.ctx.Name())
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
	LogTimef(os.Stderr, "Info: running container...\n")
	err := docker.Docker(flags, "run", args)

	// If DinD is enabled in daemon mode, inform user how to stop it
	if booth.ctx.Egress() {
		fmt.Printf("🛡️  Egress sidecar running: %s\n", getEgressProxyName(booth.ctx))
		if booth.ctx.Dind() {
			fmt.Printf("   Reusing DinD netns owner: %s\n", getDindName(booth.ctx))
		} else {
			fmt.Printf("   Netns owner sidecar: %s (network: %s)\n", getEgressNetnsName(booth.ctx), getEgressNet(booth.ctx))
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

	LogPrintln("📦 Running booth in foreground.")
	if booth.ctx.KeepAlive() {
		LogPrintln("👉 Stop with Ctrl+C. The container will be kept (no --rm).")
	} else {
		LogPrintln("👉 Stop with Ctrl+C. The container will be removed (--rm) when stop.")
	}
	LogPrintf("👉 To open an interactive shell instead: '%s -- bash'\n", booth.ctx.ScriptName())
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

	// Start TCP tunnel watcher (watches .booth/.tmp/tcp-tunnels/ for booth--expose)
	tunnelCtx, tunnelCancel := context.WithCancel(context.Background())
	if !booth.ctx.Dryrun() {
		containerName := booth.ctx.Name()
		if containerName == "" {
			containerName = booth.ctx.ProjectName()
		}
		go StartTcpTunnelWatcher(tunnelCtx, booth.ctx, containerName)
	}

	// Execute the docker run command
	LogTimef(os.Stderr, "Info: running container...\n")
	err := docker.Docker(flags, "run", args)
	LogTimef(os.Stderr, "Info: container exited.\n")

	// Stop tunnel watcher
	tunnelCancel()

	// Check for restart/idle markers before cleanup removes them
	restartRequested := checkAndCleanRestartMarker(booth.ctx)
	idleShutdown := checkAndCleanIdleShutdownMarker(booth.ctx)

	// Cleanup .booth/.tmp/ on exit (unless --leave-tmp-on-exit)
	cleanupBoothTmp(booth.ctx)

	// Cleanup egress/DinD sidecars after foreground exits.
	cleanupFlags := flags
	cleanupFlags.Silent = true
	cleanupFlags.Verbose = false
	cleanupEgressResources(booth.ctx, &cleanupFlags)
	if booth.ctx.Dind() {
		dindName := getDindName(booth.ctx)
		dindNet := getDindNet(booth.ctx)
		_ = docker.Docker(cleanupFlags, "stop", ilist.NewList(ilist.NewList(dindName)))
		if booth.ctx.CreatedDindNet() {
			_ = docker.Docker(cleanupFlags, "network", ilist.NewList(ilist.NewList("rm", dindNet)))
		}
	}

	if restartRequested {
		return &RestartRequestedError{}
	}

	if idleShutdown {
		return &IdleShutdownError{ExitCode: booth.ctx.IdleExitCode()}
	}

	printHomeVolumeWarning(booth.ctx)

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

func getHostOS() string {
	switch runtime.GOOS {
	case "windows":
		return "WIN"
	case "linux":
		return "LIN"
	case "darwin":
		return "MAC"
	default:
		return runtime.GOOS
	}
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
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "HOST_OS="+getHostOS()))
	codePath := normalizeCodePath(ctx.Code())
	createdAt := time.Now().UTC().Format(time.RFC3339)

	// Persist home directory via a Docker named volume.
	// Must be mounted BEFORE the code bind mount so /home/coder/code overlays on top.
	if ctx.PersistHome() {
		fmt.Fprintln(os.Stderr, "Warning: --persist-home is experimental. Please report issues at https://github.com/NawaMan/CodingBooth/issues")
		homeVolName := "cb-home-" + containerName
		ensureHomeVolume(ctx, homeVolName, containerName)
		builder.CommonArgs.Append(ilist.NewList[string]("-v", homeVolName+":/home/coder"))
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_HOME_PERSISTED=true"))
	}

	builder.CommonArgs.Append(ilist.NewList[string]("-v", codePath+":/home/coder/code"))
	builder.CommonArgs.Append(ilist.NewList[string]("-w", "/home/coder/code"))

	if !ctx.WritableBooth() {
		addReadOnlyBoothDir(builder, codePath)
		addReadOnlyBoothWrapper(builder, codePath)
	}

	// Lifecycle management labels used by list/start/stop/restart/remove commands.
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.managed=true"))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.project="+ctx.ProjectName()))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.variant="+ctx.Variant()))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.code-path="+codePath))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.created-at="+createdAt))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.version="+ctx.CbVersion()))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", fmt.Sprintf("cb.keep-alive=%t", ctx.KeepAlive())))
	builder.CommonArgs.Append(ilist.NewList[string]("--label", fmt.Sprintf("cb.daemon=%t", ctx.Daemon())))
	if ctx.PersistHome() {
		builder.CommonArgs.Append(ilist.NewList[string]("--label", "cb.persist-home=true"))
	}

	// Desktop variants run Chromium-based apps (VS Code, browsers) whose renderers
	// map shared memory in /dev/shm. Docker's default 64 MB is too small and the
	// renderer aborts ("renderer process gone, code 133") on heavy pages such as
	// rich notebooks. Give them room.
	if ctx.HasDesktop() {
		builder.CommonArgs.Append(ilist.NewList[string]("--shm-size", "1g"))
	}

	// Skip port mapping when using shared network namespace sidecars.
	if !ctx.Dind() && !ctx.Egress() {
		containerPort := 10000
		if ctx.Public() {
			containerPort = 10443
		}
		portMapping := formatPortMapping(ctx.Public(), ctx.PortNumber(), containerPort)
		builder.CommonArgs.Append(ilist.NewList[string]("-p", portMapping))
	}

	// Enable TLS reverse proxy when public
	if ctx.Public() {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_TLS=true"))
	}

	// Mount user-provided TLS certificates
	if ctx.TLSCert() != "" && ctx.TLSKey() != "" {
		builder.RunArgs.Append(ilist.NewList[string]("-v", ctx.TLSCert()+":/tmp/booth-tls-cert.pem:ro"))
		builder.RunArgs.Append(ilist.NewList[string]("-v", ctx.TLSKey()+":/tmp/booth-tls-key.pem:ro"))
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_TLS_CERT=/tmp/booth-tls-cert.pem"))
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_TLS_KEY=/tmp/booth-tls-key.pem"))
	}

	// Inject PASSWORD env var into the container when set
	if ctx.Password() != "" {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "PASSWORD="+ctx.Password()))
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
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_SUDO=%t", ctx.Sudo())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_EGRESS=%t", ctx.Egress())))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_DOCKERFILE="+ctx.Dockerfile()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_PROJECT_NAME="+ctx.ProjectName()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_TIMEZONE="+ctx.Timezone()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_PORT="+ctx.Port()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_ENV_FILE="+ctx.EnvFile()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_HOST_UID="+ctx.HostUID()))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_HOST_GID="+ctx.HostGID()))

	// Idle time monitoring
	if ctx.IdleTime() > 0 {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_IDLE_TIME=%d", ctx.IdleTime())))
		builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_IDLE_SHUTDOWN_TIME=%d", ctx.IdleShutdownTime())))
		builder.CommonArgs.Append(ilist.NewList[string]("-e", fmt.Sprintf("BOOTH_IDLE_EXIT_CODE=%d", ctx.IdleExitCode())))
	}

	// Custom startup script
	if ctx.Startup() != "" {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_STARTUP="+ctx.Startup()))
	}

	// Timer displays
	if ctx.ShowRunTime() != "" {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_SHOW_RUN_TIME="+ctx.ShowRunTime()))
	}
	if ctx.ShowCountDown() != "" {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_SHOW_COUNT_DOWN="+ctx.ShowCountDown()))
	}
	if ctx.CountDownExitCode() != "" {
		builder.CommonArgs.Append(ilist.NewList[string]("-e", "BOOTH_COUNT_DOWN_EXIT_CODE="+ctx.CountDownExitCode()))
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

func addReadOnlyBoothWrapper(builder *appctx.AppContextBuilder, codePath string) {
	if codePath == "" {
		return
	}
	hostPath := filepath.Join(codePath, "booth")
	info, err := os.Stat(hostPath)
	if err != nil || info.IsDir() {
		return
	}
	builder.CommonArgs.Append(ilist.NewList[string]("-v", hostPath+":/home/coder/code/booth:ro"))
}

func addReadOnlyBoothDir(builder *appctx.AppContextBuilder, codePath string) {
	if codePath == "" {
		return
	}
	hostPath := filepath.Join(codePath, ".booth")
	info, err := os.Stat(hostPath)
	if err != nil || !info.IsDir() {
		return
	}
	builder.CommonArgs.Append(ilist.NewList[string]("-v", hostPath+":/home/coder/code/.booth:ro"))

	// Mount .booth/.tmp/ as writable for runtime state (tcp-tunnels, session metadata, etc.)
	tmpPath := filepath.Join(hostPath, ".tmp")
	if info, err := os.Stat(tmpPath); err == nil && info.IsDir() {
		builder.CommonArgs.Append(ilist.NewList[string]("-v", tmpPath+":/home/coder/code/.booth/.tmp"))
	}

	// Ensure cache files/dirs declared in config.toml exist in .booth/cache/.
	ensureCacheFromConfig(filepath.Join(codePath, ".booth"))

	// Mount .booth/cache/ contents into the container based on directory structure.
	cachePath := filepath.Join(hostPath, "cache")
	if info, err := os.Stat(cachePath); err == nil && info.IsDir() {
		if err := validateCacheGitignore(codePath, cachePath); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		mounts, protected := collectCacheMounts(cachePath)
		if len(protected) > 0 {
			fmt.Fprintf(os.Stderr, "Error: %v\n", protectedPathMountsError("cache", protected))
			os.Exit(1)
		}
		for _, m := range mounts {
			builder.CommonArgs.Append(ilist.NewList[string]("-v", m.hostPath+":"+m.containerPath))
		}
	}

	// Ensure shared files/dirs declared in config.toml exist in .booth/shared/.
	ensureSharedFromConfig(filepath.Join(codePath, ".booth"))

	// Mount .booth/shared/ contents (git-friendly team state). Same layout rules
	// as cache, but intentionally NOT gitignored — live edits land in the repo.
	// Skip doc files at the tree root (e.g. README.md → would mount as /README.md).
	sharedPath := filepath.Join(hostPath, "shared")
	if info, err := os.Stat(sharedPath); err == nil && info.IsDir() {
		mounts, protected := collectCacheMounts(sharedPath)
		if len(protected) > 0 {
			fmt.Fprintf(os.Stderr, "Error: %v\n", protectedPathMountsError("shared", protected))
			os.Exit(1)
		}
		for _, m := range mounts {
			if !isMountableContainerPath(m.containerPath) {
				continue
			}
			builder.CommonArgs.Append(ilist.NewList[string]("-v", m.hostPath+":"+m.containerPath))
		}
	}
}

// cacheMount represents a bind mount derived from .booth/cache/.
type cacheMount struct {
	hostPath      string
	containerPath string
}

// ensureCacheFromConfig reads cache-files and cache-dirs from config.toml
// and creates the corresponding files/directories in .booth/cache/ if they
// don't already exist (no-clobber). This allows hand-written config.toml to
// work without requiring a separate "booth config" step.
func ensureCacheFromConfig(boothDir string) {
	configPath := filepath.Join(boothDir, "config.toml")
	data, err := os.ReadFile(configPath)
	if err != nil {
		return
	}

	var cfg struct {
		CacheFiles []string `toml:"cache-files"`
		CacheDirs  []string `toml:"cache-dirs"`
	}
	if _, err := toml.Decode(string(data), &cfg); err != nil {
		return
	}
	materializePathMounts(filepath.Join(boothDir, "cache"), cfg.CacheFiles, cfg.CacheDirs)
}

// ensureSharedFromConfig reads shared-files and shared-dirs from config.toml
// and creates the corresponding files/directories in .booth/shared/ if they
// don't already exist (no-clobber). Same shape as cache, but for git-friendly
// team-shared state.
func ensureSharedFromConfig(boothDir string) {
	configPath := filepath.Join(boothDir, "config.toml")
	data, err := os.ReadFile(configPath)
	if err != nil {
		return
	}

	var cfg struct {
		SharedFiles []string `toml:"shared-files"`
		SharedDirs  []string `toml:"shared-dirs"`
	}
	if _, err := toml.Decode(string(data), &cfg); err != nil {
		return
	}
	materializePathMounts(filepath.Join(boothDir, "shared"), cfg.SharedFiles, cfg.SharedDirs)
}

// materializePathMounts creates empty files and .mount-this dirs under baseDir (no-clobber).
func materializePathMounts(baseDir string, files, dirs []string) {
	if len(files) == 0 && len(dirs) == 0 {
		return
	}
	for _, cf := range files {
		path := filepath.Join(baseDir, cf)
		if _, err := os.Stat(path); err == nil {
			continue
		}
		os.MkdirAll(filepath.Dir(path), 0755)
		os.WriteFile(path, []byte{}, 0644)
	}
	for _, cd := range dirs {
		dirPath := filepath.Join(baseDir, cd)
		os.MkdirAll(dirPath, 0755)
		markerPath := filepath.Join(dirPath, ".mount-this")
		if _, err := os.Stat(markerPath); err == nil {
			continue
		}
		os.WriteFile(markerPath, []byte{}, 0644)
	}
}

// protectedPaths are container paths that must not be overridden by cache mounts.
var protectedPaths = []string{
	"/opt/codingbooth",
	"/home/coder/code",
}

// validateCacheGitignore enforces that .booth/cache/ is gitignored. The cache holds
// whatever the container writes to the mounted paths — shell history, browser profiles,
// and (via the /etc/cb-home override layer) live credentials such as ~/.claude/.credentials.json.
//
// It asks git rather than parsing .booth/.gitignore. A "cache/" line in that file says
// nothing about cache files that are already tracked, and gitignore does not apply to
// tracked files — so a grep reports "ignored" for a repo that is committing credentials on
// every commit. "git check-ignore" consults the index, so it reports a cache directory with
// tracked content as NOT ignored, which is what we want.
//
// Skipped when git is unavailable or the project is not a git repo: there is nothing to
// commit the cache to.
func validateCacheGitignore(codeDir, cacheDir string) error {
	gitPath, err := exec.LookPath("git")
	if err != nil {
		return nil
	}
	if err := exec.Command(gitPath, "-C", codeDir, "rev-parse", "--git-dir").Run(); err != nil {
		return nil
	}

	relPath, err := filepath.Rel(codeDir, cacheDir)
	if err != nil {
		relPath = cacheDir
	}
	relPath = filepath.ToSlash(relPath)

	// Tracked cache is the dangerous case: adding a gitignore rule will NOT untrack it, so
	// this needs its own message pointing at the only fix that works.
	if out, err := exec.Command(gitPath, "-C", codeDir, "ls-files", "--", relPath).Output(); err == nil {
		if tracked := strings.Fields(string(out)); len(tracked) > 0 {
			return fmt.Errorf(
				"%s/ is tracked by git (%d file(s), e.g. %s).\n"+
					"  Cached files can contain credentials, so this must never be committed.\n"+
					"  Untrack them (they stay on disk):  git rm -r --cached %s\n"+
					"  Then make sure '%s/' is gitignored, and rotate any credential that was committed.\n"+
					"  Refusing to start",
				relPath, len(tracked), tracked[0], relPath, relPath)
		}
	}

	if err := exec.Command(gitPath, "-C", codeDir, "check-ignore", "-q", relPath).Run(); err != nil {
		return fmt.Errorf(
			"%s/ is NOT gitignored.\n"+
				"  Cached files can contain credentials, so this must never be committed.\n"+
				"  Add 'cache/' to .booth/.gitignore (or '%s/' to the repo's .gitignore).\n"+
				"  Refusing to start",
			relPath, relPath)
	}
	return nil
}

// collectCacheMounts walks .booth/cache/ and builds bind mount entries.
// Rules:
//   - Directory with .mount-this → mount entire directory, stop traversal
//   - Files in a directory without .mount-this → individual file mounts
//   - Directories without .mount-this → traverse into them
//
// Entries landing on a protected container path are returned separately rather than mounted.
// They are a misconfiguration the caller refuses to start on: silently dropping them would
// leave the user with a cache entry that never takes effect and no idea why.
func collectCacheMounts(cacheDir string) (mounts []cacheMount, protected []string) {
	walkCacheDir(cacheDir, cacheDir, &mounts, &protected)
	return mounts, protected
}

func walkCacheDir(baseDir, dir string, mounts *[]cacheMount, protected *[]string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}

	// Check for .mount-this marker
	hasMountMarker := false
	for _, entry := range entries {
		if !entry.IsDir() && entry.Name() == ".mount-this" {
			hasMountMarker = true
			break
		}
	}

	relPath, err := filepath.Rel(baseDir, dir)
	if err != nil {
		return
	}

	if hasMountMarker && relPath != "." {
		containerPath := "/" + filepath.ToSlash(relPath)
		if isProtectedPath(containerPath) {
			*protected = append(*protected, containerPath)
		} else {
			*mounts = append(*mounts, cacheMount{
				hostPath:      dir,
				containerPath: containerPath,
			})
		}
		return // stop traversal
	}

	for _, entry := range entries {
		if entry.Name() == ".mount-this" {
			continue
		}
		fullPath := filepath.Join(dir, entry.Name())
		if entry.IsDir() {
			walkCacheDir(baseDir, fullPath, mounts, protected)
		} else {
			// Individual file mount
			fileRelPath, err := filepath.Rel(baseDir, fullPath)
			if err != nil {
				continue
			}
			containerPath := "/" + filepath.ToSlash(fileRelPath)
			if isProtectedPath(containerPath) {
				*protected = append(*protected, containerPath)
			} else {
				*mounts = append(*mounts, cacheMount{
					hostPath:      fullPath,
					containerPath: containerPath,
				})
			}
		}
	}
}

// IdleShutdownError signals that the booth was shut down due to idle timeout.
type IdleShutdownError struct {
	ExitCode int
}

func (e *IdleShutdownError) Error() string {
	return fmt.Sprintf("idle shutdown (exit code %d)", e.ExitCode)
}

// idleShutdownMarkerPath returns the host path of the idle shutdown marker file.
func idleShutdownMarkerPath(ctx appctx.AppContext) string {
	codePath := ctx.Code()
	if codePath == "" {
		return ""
	}
	return filepath.Join(codePath, ".booth", ".tmp", ".idle-shutdown")
}

// checkAndCleanIdleShutdownMarker checks if the booth was shut down due to idle timeout.
// It removes the marker file and returns true if found.
func checkAndCleanIdleShutdownMarker(ctx appctx.AppContext) bool {
	markerPath := idleShutdownMarkerPath(ctx)
	if markerPath == "" {
		return false
	}
	if _, err := os.Stat(markerPath); err != nil {
		return false
	}
	os.Remove(markerPath)
	return true
}

// restartMarkerPath returns the host path of the restart marker file.
func restartMarkerPath(ctx appctx.AppContext) string {
	codePath := ctx.Code()
	if codePath == "" {
		return ""
	}
	return filepath.Join(codePath, ".booth", ".tmp", ".restart-requested")
}

// checkAndCleanRestartMarker checks if a restart was requested from inside the container.
// It removes the marker file and returns true if found.
func checkAndCleanRestartMarker(ctx appctx.AppContext) bool {
	markerPath := restartMarkerPath(ctx)
	if markerPath == "" {
		return false
	}
	if _, err := os.Stat(markerPath); err != nil {
		return false
	}
	os.Remove(markerPath)
	return true
}

// printHomeVolumeWarning prints a notice about the persisted home volume on exit.
func printHomeVolumeWarning(ctx appctx.AppContext) {
	if !ctx.PersistHome() {
		return
	}
	containerName := ctx.Name()
	if containerName == "" {
		containerName = ctx.ProjectName()
	}
	homeVolName := "cb-home-" + containerName
	fmt.Fprintf(os.Stderr, "Info: Home volume %q persists on disk.\n", homeVolName)
	fmt.Fprintf(os.Stderr, "      To reclaim space: docker volume rm %s\n", homeVolName)
	fmt.Fprintf(os.Stderr, "      Or: booth remove %s\n", containerName)
}

// ensureHomeVolume creates a Docker named volume for persisting /home/coder.
// docker volume create is idempotent — it succeeds silently if the volume already exists.
func ensureHomeVolume(ctx appctx.AppContext, volumeName string, containerName string) {
	flags := docker.DockerFlags{Dryrun: ctx.Dryrun(), Verbose: ctx.Verbose(), Silent: true}
	_ = docker.Docker(flags, "volume", ilist.NewList(
		ilist.NewList("create"),
		ilist.NewList("--label", "cb.managed=true"),
		ilist.NewList("--label", "cb.parent="+containerName),
		ilist.NewList(volumeName),
	))
}

// removeHomeVolume removes the Docker named volume for a container's persisted home.
// Fails silently if the volume does not exist.
func removeHomeVolume(containerName string) {
	homeVolName := "cb-home-" + containerName
	flags := docker.DockerFlags{Silent: true}
	_ = docker.Docker(flags, "volume", ilist.NewList(ilist.NewList("rm", homeVolName)))
}

func isProtectedPath(containerPath string) bool {
	for _, p := range protectedPaths {
		if containerPath == p || strings.HasPrefix(containerPath, p+"/") {
			return true
		}
	}
	return false
}

// isMountableContainerPath reports whether a shared/cache tree entry should be
// bind-mounted. Docs left under .booth/shared/ (README.md, …) would otherwise
// map to "/"-rooted paths like /README.md.
func isMountableContainerPath(containerPath string) bool {
	trimmed := strings.TrimPrefix(containerPath, "/")
	if trimmed == "" {
		return false
	}
	first, _, _ := strings.Cut(trimmed, "/")
	switch first {
	case "home", "opt", "etc", "usr", "var", "tmp", "root":
		return true
	default:
		return false
	}
}

// protectedPathMountsError explains cache/shared entries that would mount over a protected
// container path: the project bind mount, or CodingBooth's own install. Either would break
// the booth in a way that is hard to trace back to a stray directory under .booth/<kind>/.
func protectedPathMountsError(kind string, protected []string) error {
	var b strings.Builder
	fmt.Fprintf(&b, ".booth/%s/ maps onto %d protected container path(s):\n", kind, len(protected))
	for _, p := range protected {
		fmt.Fprintf(&b, "  %s\t(from .booth/%s%s)\n", p, kind, p)
	}
	b.WriteString("  Mounting there would shadow the project directory or CodingBooth's own install.\n")
	fmt.Fprintf(&b, "  Remove or rename those entries under .booth/%s/.\n", kind)
	b.WriteString("  Refusing to start")
	return fmt.Errorf("%s", b.String())
}

// protectedCacheMountsError is retained for tests and callers that still name "cache".
func protectedCacheMountsError(protected []string) error {
	return protectedPathMountsError("cache", protected)
}

// formatPortMapping returns a Docker port mapping string.
// When public is false, binds to 127.0.0.1 (localhost only).
// When public is true, binds to all interfaces (0.0.0.0).
func formatPortMapping(public bool, hostPort, containerPort int) string {
	if !public {
		return fmt.Sprintf("127.0.0.1:%d:%d", hostPort, containerPort)
	}
	return fmt.Sprintf("%d:%d", hostPort, containerPort)
}

// FilterMissingVolumeMounts removes -v/--volume bind mounts whose host path does not exist.
// On Mac and Windows, Docker creates an empty directory when the host path is missing,
// which breaks container startup. Named volumes and non-path sources are left untouched.
// Applies to both RunArgs and CommonArgs (e.g. TLS cert mounts added in PrepareCommonArgs).
func FilterMissingVolumeMounts(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()
	homeDir, _ := os.UserHomeDir()
	builder.RunArgs = filterMissingVolumeMountGroups(ctx.RunArgs(), homeDir)
	builder.CommonArgs = filterMissingVolumeMountGroups(ctx.CommonArgs(), homeDir)
	return builder.Build()
}

func filterMissingVolumeMountGroups(args ilist.List[ilist.List[string]], homeDir string) *ilist.AppendableList[ilist.List[string]] {
	filtered := ilist.NewAppendableList[ilist.List[string]]()
	args.Range(func(_ int, group ilist.List[string]) bool {
		items := group.Slice()
		kept := filterMissingVolumeMountItems(items, homeDir)
		if len(kept) > 0 {
			filtered.Append(ilist.NewListFromSlice(kept))
		}
		return true
	})
	return filtered
}

func filterMissingVolumeMountItems(items []string, homeDir string) []string {
	var kept []string
	for i := 0; i < len(items); i++ {
		flag := items[i]
		if !isVolumeFlag(flag) || i+1 >= len(items) {
			kept = append(kept, flag)
			continue
		}

		mountSpec := items[i+1]
		source := volumeSource(mountSpec)

		// Named volumes and other non-path sources must not be existence-checked.
		if !isBindMountSource(source) {
			kept = append(kept, flag, mountSpec)
			i++
			continue
		}

		expandedPath := expandHostPath(source, homeDir)
		if _, err := os.Stat(expandedPath); err != nil {
			fmt.Fprintf(os.Stderr, "   Skipping volume mount: host path does not exist: %s\n", source)
			i++ // skip the value
			continue
		}

		// Prefer the expanded absolute host path so Docker does not see a raw "~".
		if expandedPath != source {
			mountSpec = expandedPath + mountSpec[len(source):]
		}
		kept = append(kept, flag, mountSpec)
		i++ // skip the value
	}
	return kept
}

func isVolumeFlag(flag string) bool {
	return flag == "-v" || flag == "--volume"
}

// volumeSource returns the host/source side of a Docker -v/--volume mount spec.
// Handles Windows drive-letter paths (C:\...:/container:ro) correctly so the first
// colon after the drive letter is not treated as the host/container separator.
func volumeSource(spec string) string {
	if spec == "" {
		return ""
	}

	// Windows absolute path: X:\... or X:/...
	if isWindowsDrivePath(spec) {
		// Linux containers: host ends at ":/" (container path is always absolute Unix).
		if i := strings.Index(spec[2:], ":/"); i >= 0 {
			return spec[:2+i]
		}
		// Windows containers: C:\host:D:\container or C:\host:C:\container
		if i := indexWindowsPathSeparatorColon(spec, 2); i >= 0 {
			return spec[:i]
		}
		return spec
	}

	// UNC host paths: \\server\share\path:/container
	if strings.HasPrefix(spec, `\\`) || strings.HasPrefix(spec, "//") {
		if i := strings.Index(spec[2:], ":/"); i >= 0 {
			return spec[:2+i]
		}
		if i := strings.Index(spec[2:], ":"); i >= 0 {
			return spec[:2+i]
		}
		return spec
	}

	// Unix / relative / named-volume: first colon separates source from target.
	if i := strings.Index(spec, ":"); i >= 0 {
		return spec[:i]
	}
	return spec
}

// isWindowsDrivePath reports whether s starts with a Windows drive absolute path (C:\ or C:/).
func isWindowsDrivePath(s string) bool {
	return len(s) >= 3 && isDriveLetter(s[0]) && s[1] == ':' && (s[2] == '\\' || s[2] == '/')
}

func isDriveLetter(b byte) bool {
	return (b >= 'A' && b <= 'Z') || (b >= 'a' && b <= 'z')
}

// indexWindowsPathSeparatorColon finds a colon that starts another Windows path (":X:\" or ":X:/").
func indexWindowsPathSeparatorColon(spec string, start int) int {
	for i := start; i+2 < len(spec); i++ {
		if spec[i] == ':' && isDriveLetter(spec[i+1]) && spec[i+2] == ':' {
			// Pattern ":C:" — check following separator if present
			if i+3 < len(spec) && (spec[i+3] == '\\' || spec[i+3] == '/') {
				return i
			}
		}
	}
	return -1
}

// isBindMountSource reports whether source looks like a host filesystem path.
// Bare names without path separators are treated as Docker named volumes.
func isBindMountSource(source string) bool {
	if source == "" {
		return false
	}
	if source == "~" || strings.HasPrefix(source, "~/") || strings.HasPrefix(source, `~\`) {
		return true
	}
	if isWindowsDrivePath(source) {
		return true
	}
	if strings.HasPrefix(source, "/") || strings.HasPrefix(source, `\`) {
		return true
	}
	if strings.HasPrefix(source, "./") || strings.HasPrefix(source, `.\`) ||
		strings.HasPrefix(source, "../") || strings.HasPrefix(source, `..\`) {
		return true
	}
	// Relative path containing a separator (e.g. "subdir/data") is a bind mount.
	if strings.ContainsAny(source, `/\`) {
		return true
	}
	// "." or ".." alone are host paths.
	if source == "." || source == ".." {
		return true
	}
	return false
}

// expandHostPath expands a leading ~ to the user home directory.
func expandHostPath(path, homeDir string) string {
	if homeDir == "" {
		return path
	}
	if path == "~" {
		return homeDir
	}
	if strings.HasPrefix(path, "~/") {
		return filepath.Join(homeDir, path[2:])
	}
	if strings.HasPrefix(path, `~\`) {
		return filepath.Join(homeDir, path[2:])
	}
	return path
}

func flattenArgs(argsList ilist.List[ilist.List[string]]) []string {
	var flattened []string
	argsList.Range(func(_ int, group ilist.List[string]) bool {
		flattened = append(flattened, group.Slice()...)
		return true
	})
	return flattened
}

// FilterMissingDevices drops `--device` run-args whose host device node does not
// exist, warning instead of letting the booth fail to start.
//
// This is the same contract FilterMissingVolumeMounts applies to bind mounts, and
// it exists for the same reason: run-args are emitted unconditionally by whatever
// template selected them, but whether a device is present is a property of the
// host, not of the project. `docker run --device /dev/kvm` on a host without KVM
// — Docker Desktop on macOS, a Linux box with virtualization disabled in BIOS, a
// nested VM without nested virt — fails before the container is created:
//
//	docker: Error response from daemon: error gathering device information ...
//	no such file or directory
//
// A selected template must never be able to stop the booth from starting. It
// degrades with a warning instead, the way google-chrome--setup.sh skips on arm64.
func FilterMissingDevices(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()
	builder.RunArgs = filterMissingDeviceGroups(ctx.RunArgs())
	builder.CommonArgs = filterMissingDeviceGroups(ctx.CommonArgs())
	return builder.Build()
}

func filterMissingDeviceGroups(args ilist.List[ilist.List[string]]) *ilist.AppendableList[ilist.List[string]] {
	filtered := ilist.NewAppendableList[ilist.List[string]]()
	args.Range(func(_ int, group ilist.List[string]) bool {
		kept := filterMissingDeviceItems(group.Slice())
		if len(kept) > 0 {
			filtered.Append(ilist.NewListFromSlice(kept))
		}
		return true
	})
	return filtered
}

func filterMissingDeviceItems(items []string) []string {
	var kept []string
	for i := 0; i < len(items); i++ {
		flag := items[i]
		if flag != "--device" || i+1 >= len(items) {
			kept = append(kept, flag)
			continue
		}

		spec := items[i+1]
		hostPath := deviceHostPath(spec)

		// Only an absolute host path can be checked. Anything else is passed
		// through untouched rather than guessed at.
		if !strings.HasPrefix(hostPath, "/") {
			kept = append(kept, flag, spec)
			i++
			continue
		}

		if _, err := os.Stat(hostPath); err != nil {
			fmt.Fprintf(os.Stderr, "⚠️  Skipping device: not present on this host: %s\n", hostPath)
			if hostPath == "/dev/kvm" {
				fmt.Fprintf(os.Stderr, "   The Android emulator will need '-accel off' (software emulation, much slower).\n")
			}
			i++ // skip the value
			continue
		}

		kept = append(kept, flag, spec)
		i++ // skip the value
	}
	return kept
}

// deviceHostPath returns the host side of a Docker --device spec.
// Forms: "/dev/kvm", "/dev/kvm:/dev/kvm", "/dev/kvm:/dev/kvm:rwm".
func deviceHostPath(spec string) string {
	if idx := strings.Index(spec, ":"); idx >= 0 {
		return spec[:idx]
	}
	return spec
}
