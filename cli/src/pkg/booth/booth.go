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
			fmt.Fprintf(os.Stderr, "Error: %v\n", protectedCacheMountsError(protected))
			os.Exit(1)
		}
		for _, m := range mounts {
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

	if len(cfg.CacheFiles) == 0 && len(cfg.CacheDirs) == 0 {
		return
	}

	cacheDir := filepath.Join(boothDir, "cache")
	for _, cf := range cfg.CacheFiles {
		path := filepath.Join(cacheDir, cf)
		if _, err := os.Stat(path); err == nil {
			continue
		}
		os.MkdirAll(filepath.Dir(path), 0755)
		os.WriteFile(path, []byte{}, 0644)
	}
	for _, cd := range cfg.CacheDirs {
		dirPath := filepath.Join(cacheDir, cd)
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

// protectedCacheMountsError explains cache entries that would mount over a protected
// container path: the project bind mount, or CodingBooth's own install. Either would break
// the booth in a way that is hard to trace back to a stray directory under .booth/cache/.
func protectedCacheMountsError(protected []string) error {
	var b strings.Builder
	fmt.Fprintf(&b, ".booth/cache/ maps onto %d protected container path(s):\n", len(protected))
	for _, p := range protected {
		fmt.Fprintf(&b, "  %s\t(from .booth/cache%s)\n", p, p)
	}
	b.WriteString("  Mounting there would shadow the project directory or CodingBooth's own install.\n")
	b.WriteString("  Remove or rename those entries under .booth/cache/.\n")
	b.WriteString("  Refusing to start")
	return fmt.Errorf("%s", b.String())
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

// FilterMissingVolumeMounts removes -v bind mounts whose host path does not exist.
// On Mac and Windows, Docker creates an empty directory when the host path is missing,
// which breaks container startup. This filters those mounts out and logs when verbose.
func FilterMissingVolumeMounts(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()
	verbose := ctx.Verbose()

	homeDir, _ := os.UserHomeDir()

	filtered := ilist.NewAppendableList[ilist.List[string]]()
	ctx.RunArgs().Range(func(_ int, group ilist.List[string]) bool {
		items := group.Slice()
		var kept []string
		for i := 0; i < len(items); i++ {
			if (items[i] == "-v" || items[i] == "--volume") && i+1 < len(items) {
				mountSpec := items[i+1]
				hostPath := mountSpec
				if idx := strings.Index(mountSpec, ":"); idx >= 0 {
					hostPath = mountSpec[:idx]
				}

				// Expand ~ to home directory
				expandedPath := hostPath
				if strings.HasPrefix(hostPath, "~/") && homeDir != "" {
					expandedPath = filepath.Join(homeDir, hostPath[2:])
				} else if hostPath == "~" && homeDir != "" {
					expandedPath = homeDir
				}

				if _, err := os.Stat(expandedPath); err != nil {
					if verbose {
						fmt.Printf("   Skipping volume mount: host path does not exist: %s\n", hostPath)
					}
					i++ // skip the value
					continue
				}
				kept = append(kept, items[i], items[i+1])
				i++ // skip the value
			} else {
				kept = append(kept, items[i])
			}
		}
		if len(kept) > 0 {
			filtered.Append(ilist.NewListFromSlice(kept))
		}
		return true
	})

	builder.RunArgs = filtered
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
