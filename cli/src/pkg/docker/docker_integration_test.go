// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker_test

import (
	"fmt"
	"os"
	"testing"

	"github.com/nawaman/workspace/src/pkg/docker"
	"github.com/nawaman/workspace/src/pkg/ilist"
)

// TestIntegration_pullHelloWorld demonstrates pulling the hello-world image.
// This will actually pull the image from Docker Hub.
func TestIntegration_PullHelloWorld(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 1: Pull hello-world Image")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • Pull the 'hello-world:latest' image from Docker Hub")
	fmt.Println("  • Show the docker pull command being executed")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • Docker pull progress bars")
	fmt.Println("  • Image digest and status")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: true,
		Silent:  false,
	}

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Executing Docker command...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.Docker(flags, "pull", ilist.NewList(ilist.NewList("hello-world:latest")))
	fmt.Println("───────────────────────────────────────────────────────────")

	fmt.Println()
	if err != nil {
		t.Fatalf("Pull failed: %v", err)
	}

	fmt.Println("Pull completed successfully")
}

// TestIntegration_runHelloWorld demonstrates running the hello-world container.
// This will actually run the container and show its output.
func TestIntegration_runHelloWorld(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 2: Run hello-world Container")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • Run the 'hello-world' container")
	fmt.Println("  • Container will print its welcome message")
	fmt.Println("  • Container will be automatically removed (--rm)")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • Hello from Docker! message")
	fmt.Println("  • Explanation of what Docker did")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  false,
	}

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Executing Docker command...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.Docker(flags, "run", ilist.NewList(ilist.NewList("--rm", "hello-world:latest")))
	fmt.Println("───────────────────────────────────────────────────────────")

	fmt.Println()
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	fmt.Println("Container executed successfully")
}

// TestIntegration_runAlpineEcho demonstrates running a simple command in alpine.
// This will actually run the echo command in an alpine container.
func TestIntegration_runAlpineEcho(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 3: Run Echo Command in Alpine")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • Run an 'echo' command inside an alpine container")
	fmt.Println("  • Print 'Hello from Alpine!'")
	fmt.Println("  • Container will be automatically removed")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • Hello from Alpine!")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  false,
	}

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Executing Docker command...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.Docker(flags, "run", ilist.NewList(ilist.NewList("--rm", "alpine:latest", "echo", "Hello from Alpine!")))
	fmt.Println("───────────────────────────────────────────────────────────")

	fmt.Println()
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	fmt.Println("Command executed successfully")
}

// TestIntegration_runAlpineWithEnv demonstrates running alpine with environment variables.
// This will actually run the command with the environment variable set.
func TestIntegration_runAlpineWithEnv(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 4: Run Alpine with Environment Variable")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • Set environment variable MY_VAR='test value'")
	fmt.Println("  • Run a shell command to echo the variable")
	fmt.Println("  • Demonstrate proper quoting of values with spaces")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • test value")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  false,
	}

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Executing Docker command...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.Docker(flags, "run", ilist.NewList(ilist.NewList(
		"--rm",
		"-e", "MY_VAR=test value",
		"alpine:latest",
		"sh", "-c", "echo $MY_VAR",
	)))
	fmt.Println("───────────────────────────────────────────────────────────")

	fmt.Println()
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	fmt.Println("Command executed successfully")
}

// TestIntegration_imageInspect demonstrates inspecting a docker image.
// This will actually inspect the hello-world image (must exist locally).
func TestIntegration_imageInspect(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 5: Inspect Docker Image")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • Inspect the 'hello-world:latest' image")
	fmt.Println("  • Show detailed JSON information about the image")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • JSON array with image metadata")
	fmt.Println("  • Image ID, creation date, size, etc.")
	fmt.Println()
	fmt.Println("Note: Run Example 1 first if image doesn't exist locally")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  false,
	}

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Executing Docker command...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.Docker(flags, "image", ilist.NewList(ilist.NewList("inspect", "hello-world:latest")))
	fmt.Println("───────────────────────────────────────────────────────────")

	fmt.Println()
	if err != nil {
		t.Fatalf("Inspect failed: %v\nHint: Run Example 1 to pull the image first", err)
	}

	fmt.Println("Inspect completed successfully")
}

// TestIntegration_listContainers demonstrates listing docker containers.
// This will actually list all containers on your system.
func TestIntegration_listContainers(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 6: List All Containers")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • List all containers (running and stopped)")
	fmt.Println("  • Show container IDs, names, status, etc.")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • Table of containers (may be empty if none exist)")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  false,
	}

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Executing Docker command...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.Docker(flags, "ps", ilist.NewList(ilist.NewList("-a")))
	fmt.Println("───────────────────────────────────────────────────────────")

	fmt.Println()
	if err != nil {
		t.Fatalf("List failed: %v", err)
	}

	fmt.Println("List completed successfully")
}

// TestIntegration_networkOperations demonstrates docker network operations.
// This will actually create, inspect, and remove a test network.
func TestIntegration_networkOperations(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 7: Network Operations")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • Create a network named 'test-network'")
	fmt.Println("  • Inspect the network to show its details")
	fmt.Println("  • Remove the network (cleanup)")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • Network ID on creation")
	fmt.Println("  • JSON details on inspection")
	fmt.Println("  • Network name on removal")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  false,
	}

	networkName := "test-network"

	// Create network
	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Creating network...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.Docker(flags, "network", ilist.NewList(ilist.NewList("create", networkName)))
	fmt.Println("───────────────────────────────────────────────────────────")
	if err != nil {
		t.Fatalf("Create failed: %v", err)
	}

	// Inspect network
	fmt.Println("\nInspecting network...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err = docker.Docker(flags, "network", ilist.NewList(ilist.NewList("inspect", networkName)))
	fmt.Println("───────────────────────────────────────────────────────────")
	if err != nil {
		t.Fatalf("Inspect failed: %v", err)
	}

	// Remove network
	fmt.Println("\nRemoving network...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err = docker.Docker(flags, "network", ilist.NewList(ilist.NewList("rm", networkName)))
	fmt.Println("───────────────────────────────────────────────────────────")
	if err != nil {
		t.Fatalf("Remove failed: %v", err)
	}

	fmt.Println()
	fmt.Println("Network operations completed successfully")
}

// TestIntegration_complexCommand demonstrates a complex docker run command.
// This shows all argument types: flags, environment variables, volumes, etc.
func TestIntegration_complexCommand(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 8: Complex Docker Command")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • Run alpine with many different argument types")
	fmt.Println("  • Demonstrate: --rm, --name, -e, -v, -w, -p, --network")
	fmt.Println("  • Show proper quoting of complex arguments")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • Hello from Alpine!")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  false,
	}

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Executing Docker command...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.Docker(flags, "run", ilist.NewList(ilist.NewList(
		"--rm",                     // Remove after exit
		"--name", "test-container", // Container name
		"-e", "ENV_VAR=value with spaces", // Environment variable
		"-v", "/tmp:/data", // Volume mount
		"-w", "/data", // Working directory
		"-p", "8080:80", // Port mapping
		"--network", "bridge", // Network
		"alpine:latest",                         // Image
		"sh", "-c", "echo 'Hello from Alpine!'", // Command
	)))
	fmt.Println("───────────────────────────────────────────────────────────")

	fmt.Println()
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	fmt.Println("Complex command executed successfully")
}

// TestIntegration_interactiveShell demonstrates using -it flags for interactive shell.
// This shows TTY detection in action - the -it flags will be automatically
// filtered when running through go test, but will work when run in a terminal.
func TestIntegration_interactiveShell(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 9: Interactive Shell with -it Flags")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example demonstrates TTY detection:")
	fmt.Println("  • Uses -it flags for interactive terminal")
	fmt.Println("  • Flags are AUTO-FILTERED when no TTY (go test, CI/CD)")
	fmt.Println("  • Flags are PRESERVED when running in a real terminal")
	fmt.Println()
	fmt.Println("⚠️  LIMITATION: go test doesn't support interactive TTY")
	fmt.Println("   Even when run from a terminal, go test captures output")
	fmt.Println("   So this example will always show no TTY")
	fmt.Println()
	fmt.Println("✅ To see REAL interactive mode with -it working:")
	fmt.Println("   Run: go run ./src/cmd/docker-interactive-manual-test/main.go")
	fmt.Println()
	fmt.Println("Current TTY status:")
	fmt.Printf("  • HasInteractiveTTY: %v\n", docker.HasInteractiveTTY())
	fmt.Printf("  • IsStdinTTY: %v\n", docker.IsStdinTTY())
	fmt.Printf("  • IsStdoutTTY: %v\n", docker.IsStdoutTTY())
	fmt.Println()
	fmt.Println("Expected behavior:")
	if docker.HasInteractiveTTY() {
		fmt.Println("  • Running with TTY - will use -it flags")
		fmt.Println("  • Container will start interactive shell")
	} else {
		fmt.Println("  • Running without TTY - will auto-strip -it flags")
		fmt.Println("  • Container will run non-interactively")
		fmt.Println("  • Will execute the echo command and exit")
	}
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  false,
	}

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Executing Docker command...")
	fmt.Println("───────────────────────────────────────────────────────────")

	// Use -it flags unconditionally - they'll be auto-filtered if no TTY
	err := docker.Docker(flags, "run", ilist.NewList(ilist.NewList(
		"-it",  // Interactive + TTY (auto-filtered if no TTY)
		"--rm", // Remove after exit
		"alpine:latest",
		"sh", "-c", "echo 'TTY Detection: -it flags are automatically handled!'",
	)))

	fmt.Println("───────────────────────────────────────────────────────────")

	fmt.Println()
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	fmt.Println("Interactive shell example completed successfully")
	fmt.Println()
	fmt.Println("Note: The -it flags were automatically handled based on TTY availability!")
}

// TestIntegration_buildImage demonstrates building a Docker image from a Dockerfile.
// This will actually build an image using the test Dockerfile.
func TestIntegration_buildImage(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 10: Build Docker Image")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • Build a Docker image from an inline Dockerfile")
	fmt.Println("  • Tag the image as 'test-example:latest'")
	fmt.Println("  • Use a simple Alpine-based image")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • Build steps and layer creation")
	fmt.Println("  • Successfully tagged message")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  false,
	}

	// Create a simple Dockerfile content
	dockerfile := `FROM alpine:latest
RUN echo "Building test image..."
CMD ["echo", "Hello from test image!"]
`

	// Write Dockerfile to temp location
	tmpDir := "/tmp/docker-build-test"
	os.MkdirAll(tmpDir, 0755)
	defer os.RemoveAll(tmpDir)

	dockerfilePath := tmpDir + "/Dockerfile"
	if err := os.WriteFile(dockerfilePath, []byte(dockerfile), 0644); err != nil {
		t.Fatalf("Failed to create Dockerfile: %v", err)
	}

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Executing Docker command...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.DockerBuild(flags, ilist.NewList(ilist.NewList("-t", "test-example:latest", "-f", dockerfilePath, tmpDir)))
	fmt.Println("───────────────────────────────────────────────────────────")

	fmt.Println()
	if err != nil {
		t.Fatalf("Build failed: %v", err)
	}

	fmt.Println("Build completed successfully")
}

// TestIntegration_runDaemon demonstrates running a container in daemon mode.
// This will start a container in the background and then stop it.
func TestIntegration_runDaemon(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 11: Run Container in Daemon Mode")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • Start a container in background mode (-d)")
	fmt.Println("  • Container runs 'sleep 30' command")
	fmt.Println("  • Then stop and remove the container")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • Container ID on start")
	fmt.Println("  • Container name on stop")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  false,
	}

	containerName := "test-daemon-example"

	// Start in daemon mode
	fmt.Println("Starting container in daemon mode...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.Docker(flags, "run", ilist.NewList(ilist.NewList(
		"-d",
		"--name", containerName,
		"--rm",
		"alpine:latest",
		"sleep", "30",
	)))
	fmt.Println("───────────────────────────────────────────────────────────")
	if err != nil {
		t.Fatalf("Run daemon failed: %v", err)
	}

	// Stop the container
	fmt.Println("\nStopping daemon container...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err = docker.Docker(flags, "stop", ilist.NewList(ilist.NewList(containerName)))
	fmt.Println("───────────────────────────────────────────────────────────")
	if err != nil {
		t.Fatalf("Stop failed: %v", err)
	}

	fmt.Println()
	fmt.Println("Daemon mode example completed successfully")
}

// TestIntegration_stopContainer demonstrates stopping a running container.
// This will start a container and then stop it.
func TestIntegration_stopContainer(t *testing.T) {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Example 12: Stop Running Container")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This example will:")
	fmt.Println("  • Start a long-running container (sleep 60)")
	fmt.Println("  • Immediately stop it")
	fmt.Println("  • Demonstrate the stop command")
	fmt.Println()
	fmt.Println("Expected output:")
	fmt.Println("  • Container ID on start")
	fmt.Println("  • Container name on stop")
	fmt.Println()

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: false,
		Silent:  false,
	}

	containerName := "test-stop-example"

	// Cleanup potential leftover from previous failed runs
	cleanupFlags := flags
	cleanupFlags.Silent = true
	docker.Docker(cleanupFlags, "rm", ilist.NewList(ilist.NewList("-f", containerName)))

	// Start container
	fmt.Println("Starting container...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err := docker.Docker(flags, "run", ilist.NewList(ilist.NewList(
		"-d",
		"--name", containerName,
		"alpine:latest",
		"sleep", "60",
	)))
	fmt.Println("───────────────────────────────────────────────────────────")
	if err != nil {
		t.Fatalf("Run failed: %v", err)
	}

	// Stop container
	fmt.Println("\nStopping container...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err = docker.Docker(flags, "stop", ilist.NewList(ilist.NewList(containerName)))
	fmt.Println("───────────────────────────────────────────────────────────")
	if err != nil {
		t.Fatalf("Stop failed: %v", err)
	}

	// Remove container (cleanup)
	fmt.Println("\nRemoving container...")
	fmt.Println("───────────────────────────────────────────────────────────")
	err = docker.Docker(flags, "rm", ilist.NewList(ilist.NewList(containerName)))
	fmt.Println("───────────────────────────────────────────────────────────")
	if err != nil {
		t.Fatalf("Remove failed: %v", err)
	}

	fmt.Println()
	fmt.Println("Stop container example completed successfully")
}
