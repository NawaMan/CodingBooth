// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker_test

import (
	"os"
	"testing"

	"github.com/nawaman/coding-booth/src/pkg/docker"
	"github.com/nawaman/coding-booth/src/pkg/ilist"
)

// TestDockerBuild_Silent tests DockerBuild with SilenceBuild enabled.
// This test will actually build a Docker image but suppress build output unless it fails.
func TestDockerBuild_Silent(t *testing.T) {

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: false,
		Silent:  true,
	}

	// Create a simple test Dockerfile
	dockerfile := `FROM alpine:latest
RUN echo "Building silently..."
CMD ["echo", "Hello"]
`

	tmpDir := t.TempDir()
	dockerfilePath := tmpDir + "/Dockerfile"
	if err := writeFile(dockerfilePath, []byte(dockerfile), 0644); err != nil {
		t.Fatalf("Failed to create Dockerfile: %v", err)
	}

	// Build with silent mode - should not show progress
	err := docker.DockerBuild(flags, ilist.NewList(ilist.NewList(
		"-t", "test-silent:latest",
		"-f", dockerfilePath,
		tmpDir,
	)))

	if err != nil {
		t.Fatalf("Silent build failed: %v", err)
	}

	t.Log("✓ Silent build completed (no output expected)")
}

// TestDockerBuild_Normal tests DockerBuild with SilenceBuild disabled.
func TestDockerBuild_Normal(t *testing.T) {

	// Define options
	flags := docker.DockerFlags{
		Dryrun:  false,
		Verbose: true,
		Silent:  false,
	}

	// Create a simple test Dockerfile
	dockerfile := `FROM alpine:latest
RUN echo "Building normally..."
CMD ["echo", "Hello"]
`

	tmpDir := t.TempDir()
	dockerfilePath := tmpDir + "/Dockerfile"
	if err := writeFile(dockerfilePath, []byte(dockerfile), 0644); err != nil {
		t.Fatalf("Failed to create Dockerfile: %v", err)
	}

	// Build with normal mode - should show progress
	err := docker.DockerBuild(flags, ilist.NewList(ilist.NewList(
		"-t", "test-normal:latest",
		"-f", dockerfilePath,
		tmpDir,
	)))

	if err != nil {
		t.Fatalf("Normal build failed: %v", err)
	}

	t.Log("✓ Normal build completed (output expected)")
}

// TestDockerBuild_Dryrun tests DockerBuild in dryrun mode.
func TestDockerBuild_Dryrun(t *testing.T) {
	// Define options
	flags := docker.DockerFlags{
		Dryrun:  true,
		Verbose: true,
		Silent:  true,
	}

	// Dryrun should not execute anything
	err := docker.DockerBuild(flags, ilist.NewList(ilist.NewList("-t", "test:latest", ".")))

	if err != nil {
		t.Fatalf("Dryrun should not fail: %v", err)
	}

	t.Log("✓ Dryrun completed (no execution)")
}

// Helper function for tests
func writeFile(path string, data []byte, perm int) error {
	return os.WriteFile(path, data, os.FileMode(perm))
}
