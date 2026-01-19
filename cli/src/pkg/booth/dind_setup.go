// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"strings"
	"time"

	"github.com/nawaman/coding-booth/src/pkg/appctx"
	"github.com/nawaman/coding-booth/src/pkg/docker"
	"github.com/nawaman/coding-booth/src/pkg/ilist"
)

// createDindNetwork creates a Docker network for DinD if it doesn't exist.
// Returns true if the network was created, false if it already existed.
func createDindNetwork(ctx appctx.AppContext, networkName string) bool {
	// Check if network already exists
	flags := docker.DockerFlags{
		Dryrun:  ctx.Dryrun(),
		Verbose: ctx.Verbose(),
		Silent:  true,
	}
	output, err := docker.DockerOutput(flags, "network", ilist.NewList(ilist.NewList("inspect", networkName)))
	if err == nil && strings.TrimSpace(output) != "" {
		// Network already exists (inspect returned data)
		return false
	}

	// Create the network
	if ctx.Verbose() {
		fmt.Printf("Creating network: %s\n", networkName)
	}

	flags.Silent = false
	err = docker.Docker(flags, "network", ilist.NewList(ilist.NewList("create", networkName)))
	if err != nil {
		fmt.Printf("Warning: failed to create network %s: %v\n", networkName, err)
		return false
	}

	return true
}

// startDindSidecar starts the DinD sidecar container if not already running.
// extraPorts contains additional port mappings (e.g., "8080:8080") from run-args.
func startDindSidecar(ctx appctx.AppContext, dindName, dindNet string, hostPort int, extraPorts []string) {
	// Check if sidecar is already running
	flags := docker.DockerFlags{
		Dryrun:  ctx.Dryrun(),
		Verbose: ctx.Verbose(),
		Silent:  true,
	}
	output, err := docker.DockerOutput(flags, "ps", ilist.NewList(ilist.NewList("--filter", fmt.Sprintf("name=^/%s$", dindName), "--format", "{{.Names}}")))

	if err == nil && strings.TrimSpace(output) == dindName {
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

	// Port mapping for the workspace container (since workspace shares DinD's network)
	portMapping := fmt.Sprintf("%d:10000", hostPort)

	var args []string
	if isDockerDesktop {
		// Docker Desktop: skip cgroup flags + /sys/fs/cgroup mount
		args = []string{
			"run", "-d", "--rm", "--privileged",
			"--name", dindName,
			"--network", dindNet,
			"-p", portMapping,
		}
	} else {
		// Native Linux: full flags
		args = []string{
			"run", "-d", "--rm", "--privileged",
			"--cgroupns=host",
			"-v", "/sys/fs/cgroup:/sys/fs/cgroup:rw",
			"--name", dindName,
			"--network", dindNet,
			"-p", portMapping,
		}
	}

	// Add extra port mappings from run-args
	for _, port := range extraPorts {
		args = append(args, "-p", port)
	}

	// Add final args (env and image)
	args = append(args, "-e", "DOCKER_TLS_CERTDIR=", "docker:dind")

	flags.Silent = false
	err = docker.Docker(flags, args[0], ilist.NewList(ilist.NewListFromSlice(args[1:])))
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
		flags := docker.DockerFlags{
			Dryrun:  ctx.Dryrun(),
			Verbose: ctx.Verbose(),
			Silent:  true,
		}
		_, err := docker.DockerOutput(flags, "run", ilist.NewList(ilist.NewList("--rm", "--network", dindNet, "docker:cli",
			"-H", fmt.Sprintf("tcp://%s:2375", dindName), "version")))

		if err == nil {
			// DinD is ready
			return
		}

		time.Sleep(250 * time.Millisecond)
	}

	fmt.Printf("⚠️  DinD did not become ready. Check: docker logs %s\n", dindName)
}

// extractPortFlags extracts -p and --publish flags from RunArgs and returns them as a slice of port mappings.
// Returns deduplicated mappings like "8080:8080" (without the -p prefix).
func extractPortFlags(runArgs ilist.List[ilist.List[string]]) []string {
	seen := make(map[string]bool)
	var ports []string
	args := runArgs.Slice()

	for _, argList := range args {
		// Iterate through all elements in the list
		for j := 0; j < argList.Length(); j++ {
			flag := argList.At(j)
			var port string

			// Check for -p or --publish with value in next element
			if (flag == "-p" || flag == "--publish") && j+1 < argList.Length() {
				port = argList.At(j+1)
				j++ // Skip the next element (the port value)
			} else if strings.HasPrefix(flag, "-p=") {
				port = strings.TrimPrefix(flag, "-p=")
			} else if strings.HasPrefix(flag, "--publish=") {
				port = strings.TrimPrefix(flag, "--publish=")
			} else if strings.HasPrefix(flag, "-p") && len(flag) > 2 {
				// Check for -p<value> (e.g., -p8080:8080)
				port = flag[2:]
			}

			// Add to result if not already seen
			if port != "" && !seen[port] {
				seen[port] = true
				ports = append(ports, port)
			}
		}
	}

	return ports
}

// stripNetworkAndPortFlags removes --network, --net, -p, and --publish flags from the argument list.
// This is needed when using container network mode, which doesn't allow port publishing.
func stripNetworkAndPortFlags(runArgs ilist.List[ilist.List[string]]) *ilist.AppendableList[ilist.List[string]] {
	result := ilist.NewAppendableList[ilist.List[string]]()
	args := runArgs.Slice()

	skipNext := false
	for _, arg := range args {
		if skipNext {
			skipNext = false
			continue
		}

		flag := arg.At(0)

		// Check for --network or --net (with value in next arg)
		if flag == "--network" || flag == "--net" {
			skipNext = true
			continue
		}

		// Check for --network=value or --net=value
		if strings.HasPrefix(flag, "--network=") || strings.HasPrefix(flag, "--net=") {
			continue
		}

		// Check for -p or --publish (with value in next arg)
		if flag == "-p" || flag == "--publish" {
			skipNext = true
			continue
		}

		// Check for -p=value or --publish=value
		if strings.HasPrefix(flag, "-p=") || strings.HasPrefix(flag, "--publish=") {
			continue
		}

		// Check for -p<value> (e.g., -p8080:8080)
		if strings.HasPrefix(flag, "-p") && len(flag) > 2 {
			continue
		}

		result.Append(arg)
	}

	return result
}
