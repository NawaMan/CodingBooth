// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package booth provides the main Booth type for managing Docker-based development environments.
package booth

import (
	"context"
	"fmt"
	"os"
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

	// Check for restart marker before cleanup removes it
	restartRequested := checkAndCleanRestartMarker(booth.ctx)

	// Cleanup .booth/.tmp/ on exit (unless --leave-tmp-on-exit)
	cleanupBoothTmp(booth.ctx)

	// Cleanup sandbox/DinD sidecars after command exits.
	cleanupFlags := flags
	cleanupFlags.Silent = true
	cleanupFlags.Verbose = false
	cleanupSandboxResources(booth.ctx, &cleanupFlags)
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

	// Check for restart marker before cleanup removes it
	restartRequested := checkAndCleanRestartMarker(booth.ctx)

	// Cleanup .booth/.tmp/ on exit (unless --leave-tmp-on-exit)
	cleanupBoothTmp(booth.ctx)

	// Cleanup sandbox/DinD sidecars after foreground exits.
	cleanupFlags := flags
	cleanupFlags.Silent = true
	cleanupFlags.Verbose = false
	cleanupSandboxResources(booth.ctx, &cleanupFlags)
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
	builder.CommonArgs.Append(ilist.NewList[string]("-v", codePath+":/home/coder/code"))
	builder.CommonArgs.Append(ilist.NewList[string]("-w", "/home/coder/code"))

	if !ctx.WritableBooth() {
		addReadOnlyBoothDir(builder, codePath)
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

	// Skip port mapping when using shared network namespace sidecars.
	if !ctx.Dind() && !ctx.Sandbox() {
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
		if err := validateCacheGitignore(hostPath); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		mounts := collectCacheMounts(cachePath)
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

// validateCacheGitignore checks that .booth/.gitignore contains a "cache/" entry.
func validateCacheGitignore(boothDir string) error {
	gitignorePath := filepath.Join(boothDir, ".gitignore")
	data, err := os.ReadFile(gitignorePath)
	if err != nil {
		return fmt.Errorf(".booth/cache/ exists but .booth/.gitignore is missing — add 'cache/' to .booth/.gitignore")
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "cache/" || line == "cache" {
			return nil
		}
	}
	return fmt.Errorf(".booth/cache/ exists but is not gitignored — add 'cache/' to .booth/.gitignore")
}

// collectCacheMounts walks .booth/cache/ and builds bind mount entries.
// Rules:
//   - Directory with .mount-this → mount entire directory, stop traversal
//   - Files in a directory without .mount-this → individual file mounts
//   - Directories without .mount-this → traverse into them
func collectCacheMounts(cacheDir string) []cacheMount {
	var mounts []cacheMount
	walkCacheDir(cacheDir, cacheDir, &mounts)
	return mounts
}

func walkCacheDir(baseDir, dir string, mounts *[]cacheMount) {
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
		if !isProtectedPath(containerPath) {
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
			walkCacheDir(baseDir, fullPath, mounts)
		} else {
			// Individual file mount
			fileRelPath, err := filepath.Rel(baseDir, fullPath)
			if err != nil {
				continue
			}
			containerPath := "/" + filepath.ToSlash(fileRelPath)
			if !isProtectedPath(containerPath) {
				*mounts = append(*mounts, cacheMount{
					hostPath:      fullPath,
					containerPath: containerPath,
				})
			}
		}
	}
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

func isProtectedPath(containerPath string) bool {
	for _, p := range protectedPaths {
		if containerPath == p || strings.HasPrefix(containerPath, p+"/") {
			fmt.Fprintf(os.Stderr, "Warning: skipping cache mount for protected path %s\n", containerPath)
			return true
		}
	}
	return false
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
