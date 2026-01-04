package docker_test

import (
	"os"
	"testing"

	"github.com/nawaman/workspace/src/pkg/docker"
)

// TestDockerBuild_Silent tests DockerBuild with SilenceBuild enabled.
// This test will actually build a Docker image but suppress build output unless it fails.
func TestDockerBuild_Silent(t *testing.T) {

	// Define options
	verbose := false
	dryrun := false
	silenceBuild := true

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
	err := docker.DockerBuild(dryrun, verbose, silenceBuild,
		"-t", "test-silent:latest",
		"-f", dockerfilePath,
		tmpDir,
	)

	if err != nil {
		t.Fatalf("Silent build failed: %v", err)
	}

	t.Log("✓ Silent build completed (no output expected)")
}

// TestDockerBuild_Normal tests DockerBuild with SilenceBuild disabled.
func TestDockerBuild_Normal(t *testing.T) {

	// Define options
	verbose := true
	dryrun := false
	silenceBuild := false

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
	err := docker.DockerBuild(dryrun, verbose, silenceBuild,
		"-t", "test-normal:latest",
		"-f", dockerfilePath,
		tmpDir,
	)

	if err != nil {
		t.Fatalf("Normal build failed: %v", err)
	}

	t.Log("✓ Normal build completed (output expected)")
}

// TestDockerBuild_Dryrun tests DockerBuild in dryrun mode.
func TestDockerBuild_Dryrun(t *testing.T) {
	// Define options
	verbose := true
	dryrun := true
	silenceBuild := true

	// Dryrun should not execute anything
	err := docker.DockerBuild(dryrun, verbose, silenceBuild, "-t", "test:latest", ".")

	if err != nil {
		t.Fatalf("Dryrun should not fail: %v", err)
	}

	t.Log("✓ Dryrun completed (no execution)")
}

// Helper function for tests
func writeFile(path string, data []byte, perm int) error {
	return os.WriteFile(path, data, os.FileMode(perm))
}
