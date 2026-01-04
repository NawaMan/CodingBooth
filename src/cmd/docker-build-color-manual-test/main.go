package main

import (
	"fmt"
	"os"

	"github.com/nawaman/workspace/src/pkg/docker"
)

func main() {
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println("Docker Build Color Manual Test")
	fmt.Println("═══════════════════════════════════════════════════════════")
	fmt.Println()
	fmt.Println("This manual test will:")
	fmt.Println("  • Build a Docker image from an inline Dockerfile")
	fmt.Println("  • Tag the image as 'color-manual-test:latest'")
	fmt.Println("  • Show Docker's colored build progress output")
	fmt.Println()
	fmt.Println("You should see:")
	fmt.Println("  • Colored progress bars (blue/green)")
	fmt.Println("  • Build steps with colors")
	fmt.Println("  • Layer caching information")
	fmt.Println()

	// Define options
	verbose := true
	dryrun := false
	silenceBuild := false

	// Create a simple Dockerfile content
	dockerfile := `FROM alpine:latest
RUN echo "Step 1: Installing packages..."
RUN echo "Step 2: Configuring application..."
RUN echo "Step 3: Setting up environment..."
CMD ["echo", "Hello from color demo!"]
`

	// Write Dockerfile to temp location
	tmpDir := "/tmp/docker-build-color-demo"
	os.MkdirAll(tmpDir, 0755)
	defer os.RemoveAll(tmpDir)

	dockerfilePath := tmpDir + "/Dockerfile"
	if err := os.WriteFile(dockerfilePath, []byte(dockerfile), 0644); err != nil {
		fmt.Printf("Failed to create Dockerfile: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println("Building Docker image...")
	fmt.Println("───────────────────────────────────────────────────────────")
	fmt.Println()

	err := docker.DockerBuild(dryrun, verbose, silenceBuild,
		"-t", "color-manual-test:latest",
		"-f", dockerfilePath,
		tmpDir,
	)

	fmt.Println()
	fmt.Println("───────────────────────────────────────────────────────────")

	if err != nil {
		fmt.Printf("Build failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Println()
	fmt.Println("✅ Build completed successfully!")
	fmt.Println()
	fmt.Println("You can now run the image with:")
	fmt.Println("  docker run --rm color-manual-test:latest")
	fmt.Println()
}
