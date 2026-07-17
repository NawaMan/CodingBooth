// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// stringSliceFlag collects repeatable -e flags into a slice.
type stringSliceFlag []string

func (f *stringSliceFlag) String() string {
	return strings.Join(*f, ", ")
}

func (f *stringSliceFlag) Set(value string) error {
	*f = append(*f, value)
	return nil
}

// connectCreateOpts holds create-time run overrides accepted by shell/exec.
// These apply only when --run creates a missing booth; against an existing booth
// they are asserted (fail by default) unless --accept-existing is set.
type connectCreateOpts struct {
	port           string // --port (empty if unset)
	acceptExisting bool   // --accept-existing: connect despite create-intent mismatch
}

// Shell opens a new interactive shell inside a running booth container.
func Shell(args []string, stderr io.Writer) error {
	positional, flags := extractPositionalAndFlags(args)

	flagSet := flag.NewFlagSet("shell", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	shell := flagSet.String("shell", "", "Shell to launch (default: container default)")
	dir := flagSet.String("dir", "", "Starting directory inside the container")
	envfile := flagSet.String("envfile", "", "Load environment variables from a file")
	run := flagSet.Bool("run", false, "Run the booth first if it is not already running")
	keepAlive := flagSet.Bool("keep-alive", false, "Keep a booth started by --run running afterwards")
	port := flagSet.String("port", "", "With --run, host port for a newly created booth (number, NEXT, or RANDOM)")
	acceptExisting := flagSet.Bool("accept-existing", false, "Connect to an existing booth even if create flags (e.g. --port) do not match")
	var envVars stringSliceFlag
	flagSet.Var(&envVars, "e", "Set environment variable (repeatable)")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(flags); err != nil {
		return commandExit(2, "")
	}

	create := connectCreateOpts{port: *port, acceptExisting: *acceptExisting}
	target, cleanup, err := resolveConnectTarget(*name, positional, *run, *keepAlive, create, stderr)
	if err != nil {
		return err
	}
	defer cleanup()
	stopCleanupSignalWatch := watchSignalsForCleanup(cleanup)
	defer stopCleanupSignalWatch()

	// Build docker exec args
	execArgs := buildExecFlags(true, *dir, envVars, *envfile)

	// Container name
	execArgs = append(execArgs, ilist.NewList(target.Name))

	// Shell command
	shellCmd := "bash"
	if *shell != "" {
		shellCmd = *shell
	}
	execArgs = append(execArgs, ilist.NewList(shellCmd, "-l"))

	if err := docker.Docker(docker.DockerFlags{Silent: false}, "exec", ilist.NewList(execArgs...)); err != nil {
		return forwardExitCode("shell", target.Name, err)
	}
	return nil
}

// Exec runs a command inside a running booth container.
func Exec(args []string, stderr io.Writer) error {
	// Split args at "--" to separate flags from the command to execute.
	beforeSep, cmdArgs := splitAtSeparator(args)

	positional, flags := extractPositionalAndFlags(beforeSep)

	flagSet := flag.NewFlagSet("exec", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	dir := flagSet.String("dir", "", "Working directory inside the container")
	interactive := flagSet.Bool("it", false, "Force interactive mode with TTY")
	envfile := flagSet.String("envfile", "", "Load environment variables from a file")
	run := flagSet.Bool("run", false, "Run the booth first if it is not already running")
	keepAlive := flagSet.Bool("keep-alive", false, "Keep a booth started by --run running afterwards")
	port := flagSet.String("port", "", "With --run, host port for a newly created booth (number, NEXT, or RANDOM)")
	acceptExisting := flagSet.Bool("accept-existing", false, "Connect to an existing booth even if create flags (e.g. --port) do not match")
	var envVars stringSliceFlag
	flagSet.Var(&envVars, "e", "Set environment variable (repeatable)")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(flags); err != nil {
		return commandExit(2, "")
	}

	if len(cmdArgs) == 0 {
		return commandExit(1, "Error: no command specified. Usage: booth exec <name> -- <command>")
	}

	create := connectCreateOpts{port: *port, acceptExisting: *acceptExisting}
	target, cleanup, err := resolveConnectTarget(*name, positional, *run, *keepAlive, create, stderr)
	if err != nil {
		return err
	}
	defer cleanup()
	stopCleanupSignalWatch := watchSignalsForCleanup(cleanup)
	defer stopCleanupSignalWatch()

	// Build docker exec args
	execArgs := buildExecFlags(*interactive, *dir, envVars, *envfile)

	// Container name
	execArgs = append(execArgs, ilist.NewList(target.Name))

	// Command to execute
	execArgs = append(execArgs, ilist.NewList(cmdArgs...))

	if err := docker.Docker(docker.DockerFlags{Silent: false}, "exec", ilist.NewList(execArgs...)); err != nil {
		return forwardExitCode("exec", target.Name, err)
	}
	return nil
}

// connectAction describes how resolveConnectTarget should make the booth
// available before connecting with shell/exec.
type connectAction int

const (
	connectUse   connectAction = iota // already running — connect as-is
	connectStart                      // exists but stopped — docker start it
	connectRun                        // does not exist — run it from scratch
)

// resolveConnectTarget makes the target booth available for shell/exec and
// returns the running container to connect to along with a cleanup function the
// caller must defer.
//
// With run=false the booth must already be running (legacy behavior). With
// run=true a stopped booth is started and a missing booth is created with
// `booth run` (in daemon mode) before connecting.
//
// Create-intent flags (e.g. --port) are applied only when a new booth is created.
// Against an existing booth they are asserted: a mismatch fails by default, or
// connects with a warning when --accept-existing is set.
//
// When --run had to change the booth's state to connect (started a stopped one
// or created a new one) and keepAlive is false, the cleanup stops the booth
// again so the session leaves no trace: a freshly-created `--rm` booth is
// removed, and a pre-existing keep-alive booth returns to stopped. A booth that
// was already running, or keepAlive=true, yields a no-op cleanup. The returned
// error is already a commandError.
func resolveConnectTarget(name string, positional []string, run, keepAlive bool, create connectCreateOpts, stderr io.Writer) (managedContainer, func(), error) {
	noCleanup := func() {}

	containers, err := managedContainers(false)
	if err != nil {
		return managedContainer{}, noCleanup, commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	target, action, err := connectPlan(containers, name, positional, run)
	if err != nil {
		return managedContainer{}, noCleanup, commandExit(1, err.Error())
	}

	// Create-intent flags only reconfigure a missing booth. Against an existing
	// one they are a contract: refuse on mismatch unless the user opts out.
	if action == connectUse || action == connectStart {
		if err := checkCreateIntentAgainstExisting(target, create, stderr); err != nil {
			return managedContainer{}, noCleanup, err
		}
	}

	switch action {
	case connectUse:
		// Already running. We did not bring it up, but it may be an ephemeral
		// booth a previous --run created — if so, join its connection count so we
		// help stop it once everyone has left (and so the booth is not torn down
		// while we are still attached).
		if !run {
			return target, noCleanup, nil
		}

	case connectStart:
		fmt.Fprintf(stderr, "Booth %q is not running; starting it...\n", target.Name)
		// Silent so docker's container-name echo does not pollute exec's stdout
		// (which is forwarded verbatim for scripting). Failures surface via err.
		if err := docker.Docker(docker.DockerFlags{Silent: true}, "start", ilist.NewList(ilist.NewList(target.Name))); err != nil {
			return managedContainer{}, noCleanup, commandExit(1, fmt.Sprintf("Error: failed to start %q: %v", target.Name, err))
		}
		// Restarting re-runs booth-entry, which re-aligns the coder user; wait so
		// the following exec does not race the passwd rewrite.
		if err := waitForBoothReady(target.Name); err != nil {
			return managedContainer{}, noCleanup, err
		}

	case connectRun:
		created, err := runConnectTarget(name, positional, keepAlive, create, stderr)
		if err != nil {
			return managedContainer{}, noCleanup, err
		}
		target = created

	default:
		return managedContainer{}, noCleanup, commandExit(1, "Error: internal error: unknown connect action")
	}

	cleanup := registerConnectSession(target.Name, action, keepAlive, stderr)
	return target, cleanup, nil
}

// checkCreateIntentAgainstExisting compares explicit create-intent flags against
// an already-existing booth. Returns a commandError on mismatch unless
// accept-existing is set (then warns and returns nil). Non-comparable values
// such as --port NEXT/RANDOM are not asserted.
func checkCreateIntentAgainstExisting(target managedContainer, create connectCreateOpts, stderr io.Writer) error {
	mismatches := createIntentMismatches(target, create)
	if len(mismatches) == 0 {
		return nil
	}

	detail := strings.Join(mismatches, "; ")
	if create.acceptExisting {
		fmt.Fprintf(stderr, "Warning: booth %q does not match create flags (%s); connecting anyway (--accept-existing).\n", target.Name, detail)
		return nil
	}

	return commandExit(1, fmt.Sprintf(
		"Error: booth %q does not match create flags (%s).\n"+
			"       Refusing to connect so the command does not run against the wrong environment.\n"+
			"       Use --accept-existing to connect anyway, or remove the booth and re-run with the desired flags.",
		target.Name, detail,
	))
}

// createIntentMismatches returns human-readable mismatch descriptions for
// explicit create-intent flags that disagree with the existing booth. Pure for
// unit tests.
func createIntentMismatches(target managedContainer, create connectCreateOpts) []string {
	var mismatches []string

	if create.port != "" && isComparablePort(create.port) {
		actual := strings.TrimSpace(target.Port)
		if actual == "" {
			mismatches = append(mismatches, fmt.Sprintf("--port %s requested but booth has no published host port", create.port))
		} else if actual != create.port {
			mismatches = append(mismatches, fmt.Sprintf("--port %s requested but booth is on port %s", create.port, actual))
		}
	}

	return mismatches
}

// isComparablePort reports whether a --port value can be asserted against a
// live booth. Symbolic NEXT/RANDOM only apply on create.
func isComparablePort(port string) bool {
	if port == "" {
		return false
	}
	upper := strings.ToUpper(port)
	if upper == "NEXT" || upper == "RANDOM" {
		return false
	}
	// Numeric (and any other explicit token users might pass) is comparable.
	return true
}

// registerConnectSession wires this shell/exec session into the booth's
// connection count and returns the cleanup to defer.
//
// Lifecycle management only applies to "ephemeral" booths — ones a --run brought
// up without --keep-alive. The session that brings such a booth up marks it
// ephemeral; every --run session attached to an ephemeral booth records a
// connection file, and on disconnect the last one out stops the booth (a
// freshly-created --rm booth is removed; a pre-existing keep-alive booth returns
// to stopped). A booth that was already running and is not ephemeral, or any
// session with --keep-alive, is never torn down.
func registerConnectSession(containerName string, action connectAction, keepAlive bool, stderr io.Writer) func() {
	noCleanup := func() {}

	// --keep-alive: make sure this booth is not (or no longer) treated as
	// ephemeral, so neither we nor any concurrent session stops it, then leave it
	// running untouched.
	if keepAlive {
		clearEphemeralMark(containerName)
		return noCleanup
	}

	broughtUp := action == connectStart || action == connectRun
	if broughtUp {
		markEphemeral(containerName)
	} else if !isEphemeral(containerName) {
		// connectUse on a booth that was already running and not managed by a
		// prior --run: leave its lifecycle entirely alone.
		return noCleanup
	}

	token := connectSessionToken()
	addConnection(containerName, token)

	var once sync.Once
	return func() {
		once.Do(func() {
			if releaseConnectionIsLast(containerName, token) {
				stopBoothQuietly(containerName, stderr)
			}
		})
	}
}

// connectPlan resolves the target booth for shell/exec and decides how to make
// it available. It is pure (no Docker) so the decision can be unit-tested.
//
// With run=false the booth must already be running. With run=true: a running
// booth is used as-is, a stopped one is started, and a missing one is created.
func connectPlan(containers []managedContainer, name string, positional []string, run bool) (managedContainer, connectAction, error) {
	if name != "" && len(positional) > 0 {
		return managedContainer{}, connectUse, errors.New("Error: use either --name or positional name, not both")
	}
	if len(positional) > 1 {
		return managedContainer{}, connectUse, errors.New("Error: too many positional arguments")
	}

	targetName := name
	if targetName == "" && len(positional) == 1 {
		targetName = positional[0]
	}
	if targetName == "" {
		targetName = defaultBoothName()
	}

	container, found := findByName(containers, targetName)
	if found && container.State == "running" {
		return container, connectUse, nil
	}

	if !run {
		if !found {
			return managedContainer{}, connectUse, fmt.Errorf("Error: booth %q not found. Use 'booth list' to see available containers.", targetName)
		}
		return managedContainer{}, connectUse, fmt.Errorf("Error: booth %q is not running.", targetName)
	}

	if found {
		return container, connectStart, nil
	}
	return managedContainer{Name: targetName}, connectRun, nil
}

// runConnectTarget creates a booth from the current workspace with `booth run`
// in daemon mode, waits for it to become ready, and returns the running
// container. It shells out to the same executable so the full run pipeline
// (config, image build, ports, …) is reused verbatim. When keepAlive is set the
// new booth is created with --keep-alive so it persists across a later stop.
// Create-intent flags (e.g. --port) are forwarded so a shell/exec --run create
// matches an equivalent booth run.
func runConnectTarget(name string, positional []string, keepAlive bool, create connectCreateOpts, stderr io.Writer) (managedContainer, error) {
	self, err := os.Executable()
	if err != nil {
		return managedContainer{}, commandExit(1, fmt.Sprintf("Error: failed to locate booth executable: %v", err))
	}

	explicitName := name
	if explicitName == "" && len(positional) == 1 {
		explicitName = positional[0]
	}

	runArgs := buildConnectRunArgs(explicitName, keepAlive, create)

	fmt.Fprintf(stderr, "No running booth found; starting one with 'booth run'...\n")

	cmd := exec.Command(self, runArgs...)
	// Route the run pipeline's output to stderr so exec's stdout stays clean.
	cmd.Stdout = stderr
	cmd.Stderr = stderr
	if err := cmd.Run(); err != nil {
		return managedContainer{}, commandExit(1, fmt.Sprintf("Error: failed to run booth: %v", err))
	}

	// Re-query and resolve the container the run just created. When no name was
	// given, resolve by the current working directory's code path so we match
	// however the run derived the name (e.g. from config.toml).
	containers, err := managedContainers(false)
	if err != nil {
		return managedContainer{}, commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	var target managedContainer
	if explicitName != "" {
		target, err = resolveSingleContainer(containers, explicitName, "", nil, stateRunning)
	} else {
		cwd, cwdErr := os.Getwd()
		if cwdErr != nil {
			return managedContainer{}, commandExit(1, fmt.Sprintf("Error: failed to determine working directory: %v", cwdErr))
		}
		target, err = resolveSingleContainer(containers, "", cwd, nil, stateRunning)
	}
	if err != nil {
		return managedContainer{}, commandExit(1, err.Error())
	}

	if err := waitForBoothReady(target.Name); err != nil {
		return managedContainer{}, err
	}
	return target, nil
}

// stopBoothQuietly tears a booth down by shelling out to `booth stop`, which
// removes a non-keep-alive (--rm) booth and returns a keep-alive one to stopped.
// Output goes to stderr; failures are reported there but otherwise ignored, as
// this runs as deferred cleanup where there is nothing left to abort.
func stopBoothQuietly(containerName string, stderr io.Writer) {
	self, err := os.Executable()
	if err != nil {
		fmt.Fprintf(stderr, "Warning: could not stop booth %q: %v\n", containerName, err)
		return
	}
	fmt.Fprintf(stderr, "Stopping booth %q...\n", containerName)
	cmd := exec.Command(self, "stop", containerName)
	cmd.Stdout = stderr
	cmd.Stderr = stderr
	if err := cmd.Run(); err != nil {
		fmt.Fprintf(stderr, "Warning: failed to stop booth %q: %v\n", containerName, err)
	}
}

// connectSessionDir is the in-container (tmpfs) directory where shell/exec
// sessions record connection state for an ephemeral --run booth. It holds an
// "ephemeral" marker and one "conn.<token>" file per attached --run session.
// Living on /run means it is wiped whenever the container restarts, so stale
// state never survives a stop.
const connectSessionDir = "/run/booth-run"

// connectSessionToken returns an identifier unique to this connection process.
func connectSessionToken() string {
	return fmt.Sprintf("%d-%d", os.Getpid(), time.Now().UnixNano())
}

// dockerExecRootQuiet runs a shell snippet in the container as root, discarding
// output, and reports whether it exited zero. Root avoids any dependence on the
// coder user's mid-alignment state for this bookkeeping.
func dockerExecRootQuiet(containerName, script string) bool {
	cmd := exec.Command("docker", "exec", "-u", "root", containerName, "sh", "-c", script)
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	return cmd.Run() == nil
}

// markEphemeral records that this booth was brought up by --run and should be
// stopped once the last connection leaves.
func markEphemeral(containerName string) {
	dockerExecRootQuiet(containerName, "mkdir -p "+connectSessionDir+" && : > "+connectSessionDir+"/ephemeral")
}

// clearEphemeralMark promotes a booth to persistent so no session stops it
// (used by --keep-alive).
func clearEphemeralMark(containerName string) {
	dockerExecRootQuiet(containerName, "rm -f "+connectSessionDir+"/ephemeral")
}

// isEphemeral reports whether the booth is currently marked ephemeral.
func isEphemeral(containerName string) bool {
	return dockerExecRootQuiet(containerName, "[ -e "+connectSessionDir+"/ephemeral ]")
}

// addConnection records this session as an active connection to the booth.
func addConnection(containerName, token string) {
	dockerExecRootQuiet(containerName, "mkdir -p "+connectSessionDir+" && : > "+connectSessionDir+"/conn."+token)
}

// releaseConnectionIsLast removes this session's connection record and reports
// whether the booth should now be stopped: true only when the booth is still
// marked ephemeral and no other connections remain. A failed exec (e.g. the
// container is already gone because another session stopped it) reports false.
func releaseConnectionIsLast(containerName, token string) bool {
	script := strings.Join([]string{
		"rm -f " + connectSessionDir + "/conn." + token,
		"[ -e " + connectSessionDir + "/ephemeral ] || exit 1",
		"for f in " + connectSessionDir + "/conn.*; do [ -e \"$f\" ] && exit 1; done",
		"exit 0",
	}, "\n")
	return dockerExecRootQuiet(containerName, script)
}

// watchSignalsForCleanup runs cleanup if the process is interrupted (SIGINT or
// SIGTERM) before the connection returns normally — e.g. Ctrl+C during a
// non-interactive `exec`, where the signal reaches this process rather than the
// in-container shell. It returns a stop function the caller must defer to tear
// the watcher down once the connection has finished. cleanup is expected to be
// idempotent, since the deferred cleanup may also run.
func watchSignalsForCleanup(cleanup func()) func() {
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	done := make(chan struct{})
	go func() {
		select {
		case <-sigCh:
			cleanup()
			os.Exit(130)
		case <-done:
		}
	}()
	return func() {
		signal.Stop(sigCh)
		close(done)
	}
}

// waitForBoothReady blocks until the booth's container has finished aligning the
// coder user. On startup booth-entry rewrites /etc/passwd to remap coder onto
// the host UID (the base image ships coder at a build-time UID, e.g. 1001, while
// Ubuntu's default user holds 1000). Connecting during that rewrite races it and
// can hit a transient window where coder's UID has no passwd name ("cannot find
// name for user ID …"). We wait until coder has settled at its final UID before
// connecting.
//
// On Unix the final UID is the invoking host user's UID (what booth-entry aligns
// to), so we poll until `id -u coder` reports exactly that. Where the host UID is
// not meaningful (Windows, os.Getuid() == -1) we instead wait for coder's UID to
// hold steady across several probes.
func waitForBoothReady(containerName string) error {
	const attempts = 120
	const interval = 500 * time.Millisecond

	coderUID := func() (string, bool) {
		out, err := exec.Command("docker", "exec", containerName, "id", "-u", "coder").Output()
		if err != nil {
			return "", false
		}
		return strings.TrimSpace(string(out)), true
	}

	if hostUID := os.Getuid(); hostUID >= 0 {
		want := strconv.Itoa(hostUID)
		for attempt := 0; attempt < attempts; attempt++ {
			if uid, ok := coderUID(); ok && uid == want {
				return nil
			}
			time.Sleep(interval)
		}
		return commandExit(1, fmt.Sprintf("Error: booth %q did not become ready in time.", containerName))
	}

	// Host UID unavailable (e.g. Windows): require the UID to be stable.
	last := ""
	stable := 0
	for attempt := 0; attempt < attempts; attempt++ {
		if uid, ok := coderUID(); ok && uid != "" {
			if uid == last {
				if stable++; stable >= 3 {
					return nil
				}
			} else {
				stable = 1
			}
			last = uid
		} else {
			stable = 0
			last = ""
		}
		time.Sleep(interval)
	}
	return commandExit(1, fmt.Sprintf("Error: booth %q did not become ready in time.", containerName))
}

// buildExecFlags constructs the common docker exec flags for both shell and exec.

// buildExecFlags constructs the common docker exec flags for both shell and exec.
func buildExecFlags(interactive bool, dir string, envVars stringSliceFlag, envfile string) []ilist.List[string] {
	var execArgs []ilist.List[string]

	// TTY flags
	if interactive && docker.HasInteractiveTTY() {
		execArgs = append(execArgs, ilist.NewList("-it"))
	} else if interactive {
		execArgs = append(execArgs, ilist.NewList("-i"))
	}

	// User and working directory
	userDir := []string{"-u", "coder"}
	if dir != "" {
		userDir = append(userDir, "-w", dir)
	} else {
		userDir = append(userDir, "-w", "/home/coder/code")
	}
	execArgs = append(execArgs, ilist.NewList(userDir...))

	// Environment variables
	for _, env := range envVars {
		execArgs = append(execArgs, ilist.NewList("-e", env))
	}

	// Environment file
	if envfile != "" {
		execArgs = append(execArgs, ilist.NewList("--env-file", envfile))
	}

	return execArgs
}

// buildConnectRunArgs builds the argv for `booth run` when shell/exec creates a
// missing booth. Always daemon mode so the process returns and shell/exec can
// attach. Pure for unit tests.
func buildConnectRunArgs(explicitName string, keepAlive bool, create connectCreateOpts) []string {
	runArgs := []string{"run", "--daemon"}
	if keepAlive {
		runArgs = append(runArgs, "--keep-alive")
	}
	if explicitName != "" {
		runArgs = append(runArgs, "--name", explicitName)
	}
	if create.port != "" {
		runArgs = append(runArgs, "--port", create.port)
	}
	return runArgs
}

// extractPositionalAndFlags separates positional arguments from flags.
// Go's flag.Parse stops at the first positional arg, so flags after a positional
// arg are never parsed. This function pulls out non-flag args (positional) and
// returns the remaining flags for flag.Parse.
// Flags that take a value (-e VAL, --name VAL) consume the next arg.
func extractPositionalAndFlags(args []string) (positional []string, flags []string) {
	knownValueFlags := map[string]bool{
		"-e": true, "--name": true, "--shell": true,
		"--dir": true, "--envfile": true, "--port": true,
	}

	for i := 0; i < len(args); i++ {
		arg := args[i]
		if strings.HasPrefix(arg, "-") {
			flags = append(flags, arg)
			// If this flag takes a value, consume the next arg too
			// (including --flag=value forms, which are a single token).
			if !strings.Contains(arg, "=") && knownValueFlags[arg] && i+1 < len(args) {
				i++
				flags = append(flags, args[i])
			}
		} else {
			positional = append(positional, arg)
		}
	}
	return
}

// splitAtSeparator splits args into two slices at the first "--" separator.
// Returns (before, after). If no "--" is found, returns (args, nil).
func splitAtSeparator(args []string) ([]string, []string) {
	for i, arg := range args {
		if arg == "--" {
			return args[:i], args[i+1:]
		}
	}
	return args, nil
}

// forwardExitCode extracts the exit code from a DockerExitError and returns
// a commandError with that code so the caller can propagate it.
func forwardExitCode(command string, containerName string, err error) error {
	var dockerErr *docker.DockerExitError
	if errors.As(err, &dockerErr) {
		return commandExit(dockerErr.ExitCode, "")
	}
	return commandExit(1, fmt.Sprintf("Error: failed to %s in %q: %v", command, containerName, err))
}

// ExecExitCode extracts the exit code from a docker exec error.
// Returns -1 if the error is not an exec.ExitError.
func ExecExitCode(err error) int {
	if exitErr, ok := err.(*exec.ExitError); ok {
		return exitErr.ExitCode()
	}
	return -1
}
