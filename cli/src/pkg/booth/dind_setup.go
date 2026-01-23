// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// cleanupPreviousBoothInstances cleans up any leftover containers and networks from previous booth runs.
// This helps prevent port conflicts when restarting the booth.
func cleanupPreviousBoothInstances(ctx appctx.AppContext, projectName string) {
	if ctx.Dryrun() {
		return
	}

	// Find and stop/remove any containers matching the project name pattern
	// This includes both the main booth container and any DinD sidecars
	patterns := []string{
		projectName,                    // Main booth container
		projectName + "-*-dind",        // DinD sidecar containers (e.g., project-10000-dind)
	}

	for _, pattern := range patterns {
		// Find containers matching the pattern
		output, err := exec.Command("docker", "ps", "-aq", "--filter", "name=^"+pattern+"$").Output()
		if err == nil && len(strings.TrimSpace(string(output))) > 0 {
			containerIDs := strings.Fields(string(output))
			for _, id := range containerIDs {
				if ctx.Verbose() {
					fmt.Printf("Stopping leftover container: %s\n", id)
				}
				exec.Command("docker", "stop", id).Run()
				exec.Command("docker", "rm", "-f", id).Run()
			}
		}

		// Also check for containers with the pattern (for wildcard matching)
		if strings.Contains(pattern, "*") {
			// Use filter with regex-like matching
			filterPattern := strings.ReplaceAll(pattern, "*", ".*")
			output, err = exec.Command("docker", "ps", "-aq", "--filter", "name="+filterPattern).Output()
			if err == nil && len(strings.TrimSpace(string(output))) > 0 {
				containerIDs := strings.Fields(string(output))
				for _, id := range containerIDs {
					// Get container name to log it
					nameOutput, _ := exec.Command("docker", "inspect", "--format", "{{.Name}}", id).Output()
					containerName := strings.TrimPrefix(strings.TrimSpace(string(nameOutput)), "/")

					if ctx.Verbose() {
						fmt.Printf("Stopping leftover container: %s (%s)\n", containerName, id)
					} else {
						fmt.Printf("Cleaning up leftover container: %s\n", containerName)
					}
					exec.Command("docker", "stop", id).Run()
					exec.Command("docker", "rm", "-f", id).Run()
				}
			}
		}
	}

	// Find and remove any networks matching the project name pattern
	output, err := exec.Command("docker", "network", "ls", "--filter", "name="+projectName, "--format", "{{.Name}}").Output()
	if err == nil && len(strings.TrimSpace(string(output))) > 0 {
		networks := strings.Fields(string(output))
		for _, network := range networks {
			// Only remove networks that look like booth networks (contain -net suffix)
			if strings.HasSuffix(network, "-net") && strings.HasPrefix(network, projectName) {
				if ctx.Verbose() {
					fmt.Printf("Removing leftover network: %s\n", network)
				}
				exec.Command("docker", "network", "rm", network).Run()
			}
		}
	}
}

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
// Returns an error if the sidecar fails to start.
func startDindSidecar(ctx appctx.AppContext, dindName, dindNet string, hostPort int, extraPorts []string) error {
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
		return nil
	}

	if ctx.Verbose() {
		fmt.Printf("Starting DinD sidecar: %s\n", dindName)
	}

	// Detect if running on Docker Desktop
	isDockerDesktop := isDockerDesktop(ctx)

	// Port mapping for the booth container (since booth shares DinD's network)
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
		return fmt.Errorf("failed to start DinD sidecar: %w", err)
	}
	return nil
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
				port = argList.At(j + 1)
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

	for _, argList := range args {
		// Build a filtered list for each inner list
		filtered := ilist.NewAppendableList[string]()
		skipNext := false

		for j := 0; j < argList.Length(); j++ {
			if skipNext {
				skipNext = false
				continue
			}

			flag := argList.At(j)

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

			filtered.Append(flag)
		}

		// Only add non-empty filtered lists to the result
		if filtered.Length() > 0 {
			result.Append(filtered.ToList())
		}
	}

	return result
}

// PortConflictError represents a port conflict with diagnostic information.
type PortConflictError struct {
	Port        string
	ProcessInfo string
	Suggestion  string
}

func (e *PortConflictError) Error() string {
	return fmt.Sprintf("port %s is already in use", e.Port)
}

// parsePortFromMapping extracts the host port from a port mapping string.
// Handles formats like "8080:80", "8080", "0.0.0.0:8080:80", "[::]:8080:80", etc.
func parsePortFromMapping(mapping string) string {
	// Handle IPv6 addresses in brackets (e.g., "[::]:8080:80")
	if strings.HasPrefix(mapping, "[") {
		// Find the closing bracket
		closeBracket := strings.Index(mapping, "]")
		if closeBracket != -1 && closeBracket+1 < len(mapping) {
			// Skip past the bracket and colon, e.g., "[::]:8080:80" -> "8080:80"
			rest := mapping[closeBracket+1:]
			if strings.HasPrefix(rest, ":") {
				rest = rest[1:]
			}
			parts := strings.Split(rest, ":")
			if len(parts) >= 1 {
				return parts[0]
			}
		}
	}

	// Remove any IP prefix (e.g., "0.0.0.0:8080:80" -> "8080:80")
	parts := strings.Split(mapping, ":")
	if len(parts) >= 2 {
		// Could be "host:container" or "ip:host:container"
		if len(parts) == 3 {
			return parts[1] // ip:host:container -> return host
		}
		return parts[0] // host:container -> return host
	}
	return mapping // just a single port
}

// checkPortInUse checks if a port is in use and returns diagnostic information.
// Returns nil if the port is free.
func checkPortInUse(port string) *PortConflictError {
	// Try ss command first (more common on modern Linux)
	output, err := exec.Command("ss", "-tlnp").Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.Contains(line, ":"+port+" ") || strings.Contains(line, ":"+port+"\t") {
				processInfo := parseProcessFromSS(line)

				// If ss couldn't identify the process, try to detect Docker
				if processInfo == "unknown process" {
					// First check if it's a running Docker container
					containerName := getDockerContainerUsingPort(port)
					if containerName != "" {
						processInfo = fmt.Sprintf("Docker container '%s'", containerName)
						suggestion := fmt.Sprintf(`This port is used by Docker container '%s'.

   To stop this container:
   docker stop %s

   Or use a different port in your config.`, containerName, containerName)
						return &PortConflictError{
							Port:        port,
							ProcessInfo: processInfo,
							Suggestion:  suggestion,
						}
					}

					// Check if it's an orphaned docker-proxy
					if isDockerProxy(port) {
						processInfo = "docker-proxy (orphaned)"
						return &PortConflictError{
							Port:        port,
							ProcessInfo: processInfo,
							Suggestion:  getSuggestionForPort(port, "docker-proxy"),
						}
					}
				}

				return &PortConflictError{
					Port:        port,
					ProcessInfo: processInfo,
					Suggestion:  getSuggestionForPort(port, line),
				}
			}
		}
	}

	// Fallback to lsof if ss didn't find anything
	output, err = exec.Command("lsof", "-i", ":"+port).Output()
	if err == nil && len(output) > 0 {
		return &PortConflictError{
			Port:        port,
			ProcessInfo: parseProcessFromLsof(string(output)),
			Suggestion:  getSuggestionForPort(port, string(output)),
		}
	}

	return nil
}

// isDockerProxy checks if a port is held by a docker-proxy process or Docker container.
// This is useful when ss -tlnp doesn't show process info (requires root).
func isDockerProxy(port string) bool {
	// Check if any Docker container has this port mapped
	output, err := exec.Command("docker", "ps", "--format", "{{.Ports}}").Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			// Port mappings look like "0.0.0.0:3000->3000/tcp" or ":::3000->3000/tcp"
			if strings.Contains(line, ":"+port+"->") {
				return true
			}
		}
	}

	// Also check ps output for docker-proxy processes
	output, err = exec.Command("bash", "-c", "ps aux 2>/dev/null | grep docker-proxy | grep -v grep | grep -E 'host-port[= ]"+port+"'").Output()
	if err == nil && len(output) > 0 {
		return true
	}

	return false
}

// getDockerContainerUsingPort returns the name of the Docker container using a port, or empty string.
func getDockerContainerUsingPort(port string) string {
	output, err := exec.Command("docker", "ps", "--format", "{{.Names}}\t{{.Ports}}").Output()
	if err == nil {
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			if strings.Contains(line, ":"+port+"->") {
				parts := strings.SplitN(line, "\t", 2)
				if len(parts) >= 1 {
					return parts[0]
				}
			}
		}
	}
	return ""
}

// parseProcessFromSS extracts process information from ss output line.
func parseProcessFromSS(line string) string {
	// ss output format includes process info in users:(("process",pid=123,fd=4))
	if idx := strings.Index(line, "users:"); idx != -1 {
		return strings.TrimSpace(line[idx:])
	}
	return "unknown process"
}

// parseProcessFromLsof extracts process information from lsof output.
func parseProcessFromLsof(output string) string {
	lines := strings.Split(output, "\n")
	if len(lines) > 1 {
		// First line is header, second line has process info
		fields := strings.Fields(lines[1])
		if len(fields) >= 2 {
			return fmt.Sprintf("%s (PID: %s)", fields[0], fields[1])
		}
	}
	return "unknown process"
}

// getSuggestionForPort returns a suggestion based on what's using the port.
func getSuggestionForPort(port string, processInfo string) string {
	lowerInfo := strings.ToLower(processInfo)

	// Check for docker-proxy (orphaned Docker port binding)
	if strings.Contains(lowerInfo, "docker-proxy") {
		return fmt.Sprintf(`This port is held by an orphaned docker-proxy process.
   This usually happens when a container was removed but the proxy wasn't cleaned up.

   To fix, either:
   1. Restart Docker:     sudo systemctl restart docker
   2. Or kill the proxy:  sudo kill $(pgrep -f 'docker-proxy.*%s')`, port)
	}

	// Check for common development servers
	if strings.Contains(lowerInfo, "node") || strings.Contains(lowerInfo, "npm") {
		return "This port is used by a Node.js process. Stop the dev server or use a different port."
	}
	if strings.Contains(lowerInfo, "python") {
		return "This port is used by a Python process. Stop the server or use a different port."
	}
	if strings.Contains(lowerInfo, "java") {
		return "This port is used by a Java process. Stop the application or use a different port."
	}
	if strings.Contains(lowerInfo, "docker") {
		return "This port is used by another Docker container. Stop that container or use a different port."
	}

	// Generic suggestion
	return fmt.Sprintf(`To find what's using port %s:
   lsof -i :%s
   ss -tlnp | grep %s

   Then either stop that process or change the port in your config.`, port, port, port)
}

// diagnosePortConflict checks if any of the requested ports are already in use.
// Returns the conflicting port and diagnostic message, or empty strings if no port conflict found.
// Note: Docker's error message goes to stderr and isn't captured in the error object,
// so we proactively check all ports rather than parsing the error message.
func diagnosePortConflict(err error, hostPort int, extraPorts []string) (string, string) {
	if err == nil {
		return "", ""
	}

	// Build list of all ports we're trying to bind
	portsToCheck := []string{fmt.Sprintf("%d", hostPort)}
	for _, p := range extraPorts {
		portsToCheck = append(portsToCheck, parsePortFromMapping(p))
	}

	// Check each port and find the one that's actually in use
	for _, port := range portsToCheck {
		if conflict := checkPortInUse(port); conflict != nil {
			return port, fmt.Sprintf("Port %s is already in use by: %s\n\n   %s",
				port, conflict.ProcessInfo, conflict.Suggestion)
		}
	}

	// If no specific port conflict found, try to extract from error message as fallback
	errStr := err.Error()
	portPattern := regexp.MustCompile(`(?:port[s]?[^0-9]*|:)(\d+)`)
	matches := portPattern.FindAllStringSubmatch(errStr, -1)

	if len(matches) > 0 {
		conflictPort := matches[len(matches)-1][1]
		return conflictPort, fmt.Sprintf(`Port %s may be in use.

   To find what's using it:
   lsof -i :%s
   ss -tlnp | grep %s`, conflictPort, conflictPort, conflictPort)
	}

	return "", ""
}
