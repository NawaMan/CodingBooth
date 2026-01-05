package workspace

import (
	"fmt"
	"strings"
	"time"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/docker"
	"github.com/nawaman/workspace/src/pkg/ilist"
)

// createDindNetwork creates a Docker network for DinD if it doesn't exist.
// Returns true if the network was created, false if it already existed.
func createDindNetwork(ctx appctx.AppContext, networkName string) bool {
	// Check if network already exists
	err := docker.Docker(ctx.Dryrun(), ctx.Verbose(), "network", "inspect", networkName)
	if err == nil {
		// Network already exists
		return false
	}

	// Create the network
	if ctx.Verbose() {
		fmt.Printf("Creating network: %s\n", networkName)
	}

	err = docker.Docker(ctx.Dryrun(), ctx.Verbose(), "network", "create", networkName)
	if err != nil {
		fmt.Printf("Warning: failed to create network %s: %v\n", networkName, err)
		return false
	}

	return true
}

// startDindSidecar starts the DinD sidecar container if not already running.
func startDindSidecar(ctx appctx.AppContext, dindName, dindNet string) {
	// Check if sidecar is already running
	err := docker.Docker(ctx.Dryrun(), ctx.Verbose(), "ps", "--filter", fmt.Sprintf("name=^/%s$", dindName), "--format", "{{.Names}}")
	if err == nil {
		// Container is running
		if ctx.Verbose() {
			fmt.Printf("DinD sidecar already running: %s\n", dindName)
		}
		return
	}

	if ctx.Verbose() {
		fmt.Printf("Starting DinD sidecar: %s\n", dindName)
	}

	// Detect if running on Docker Desktop
	isDockerDesktop := isDockerDesktop(ctx)

	var args []string
	if isDockerDesktop {
		// Docker Desktop: skip cgroup flags + /sys/fs/cgroup mount
		args = []string{
			"run", "-d", "--rm", "--privileged",
			"--name", dindName,
			"--network", dindNet,
			"-e", "DOCKER_TLS_CERTDIR=",
			"docker:dind",
		}
	} else {
		// Native Linux: full flags
		args = []string{
			"run", "-d", "--rm", "--privileged",
			"--cgroupns=host",
			"-v", "/sys/fs/cgroup:/sys/fs/cgroup:rw",
			"--name", dindName,
			"--network", dindNet,
			"-e", "DOCKER_TLS_CERTDIR=",
			"docker:dind",
		}
	}

	err = docker.Docker(ctx.Dryrun(), ctx.Verbose(), args[0], args[1:]...)
	if err != nil {
		fmt.Printf("Warning: failed to start DinD sidecar: %v\n", err)
	}
}

// isDockerDesktop detects if running on Docker Desktop (macOS/Windows).
func isDockerDesktop(ctx appctx.AppContext) bool {
	// Run docker info and check for "Docker Desktop"
	// This is a simplified version - in production you'd capture output
	// For now, we'll assume native Linux (can be enhanced later)
	return false
}

// waitForDindReady waits for the DinD daemon to become ready.
func waitForDindReady(ctx appctx.AppContext, dindName, dindNet string) {
	if ctx.Dryrun() {
		return
	}

	if ctx.Verbose() {
		fmt.Printf("Waiting for DinD to become ready at tcp://%s:2375 ...\n", dindName)
	}

	maxAttempts := 40
	for i := 0; i < maxAttempts; i++ {
		// Try to connect to DinD daemon
		err := docker.Docker(ctx.Dryrun(), ctx.Verbose(), "run", "--rm", "--network", dindNet, "docker:cli",
			"-H", fmt.Sprintf("tcp://%s:2375", dindName), "version")

		if err == nil {
			// DinD is ready
			return
		}

		time.Sleep(250 * time.Millisecond)
	}

	fmt.Printf("⚠️  DinD did not become ready. Check: docker logs %s\n", dindName)
}

// stripNetworkFlags removes --network and --net flags from the argument list.
func stripNetworkFlags(runArgs ilist.List[string]) *ilist.AppendableList[string] {
	result := ilist.NewAppendableList[string]()
	args := runArgs.Slice()

	skipNext := false
	for _, arg := range args {
		if skipNext {
			skipNext = false
			continue
		}

		// Check for --network or --net (with value in next arg)
		if arg == "--network" || arg == "--net" {
			skipNext = true
			continue
		}

		// Check for --network=value or --net=value
		if strings.HasPrefix(arg, "--network=") || strings.HasPrefix(arg, "--net=") {
			continue
		}

		result.Append(arg)
	}

	return result
}
