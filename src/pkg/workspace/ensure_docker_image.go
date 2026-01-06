package workspace

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/docker"
)

// EnsureDockerImage ensures the Docker image is available and returns updated AppContext.
func EnsureDockerImage(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	// Step 1: Determine image mode
	if ctx.Image() != "" {
		// IMAGE_NAME is explicitly set
		builder.ImageMode = "EXISTING"
		builder.LocalBuild = false
	} else {
		// Normalize DOCKER_FILE
		dockerFile := normalizeDockerFile(ctx)
		builder.Config.Dockerfile = dockerFile

		if dockerFile != "" {
			// Validate it's a file
			if !isFile(dockerFile) {
				fmt.Fprintf(os.Stderr, "DOCKER_FILE (%s) is not a file.\n", dockerFile)
				os.Exit(1)
			}
			builder.ImageMode = "LOCAL-BUILD"
			builder.LocalBuild = true
		} else {
			builder.ImageMode = "PREBUILT"
			builder.LocalBuild = false
		}
	}

	// Step 2: Construct image name if not set
	ctx = builder.Build()

	if ctx.Image() == "" {
		builder = ctx.ToBuilder()
		if ctx.ImageMode() == "LOCAL-BUILD" {
			builder.Config.Image = fmt.Sprintf("workspace-local:%s-%s-%s",
				ctx.ProjectName(), ctx.Variant(), ctx.Version())
		} else {
			// PREBUILT
			builder.Config.Image = fmt.Sprintf("%s:%s-%s",
				ctx.PrebuildRepo(), ctx.Variant(), ctx.Version())
		}
		ctx = builder.Build()
	}

	// Step 3: Build local image if needed
	if ctx.LocalBuild() {
		buildLocalImage(ctx)
	}

	// Step 4: Pull image if needed (non-local-build only)
	if !ctx.LocalBuild() {
		pullImageIfNeeded(ctx)
	}

	// Step 5: Final validation
	validateImageExists(ctx)

	return ctx
}

// normalizeDockerFile normalizes the DOCKER_FILE path.
func normalizeDockerFile(ctx appctx.AppContext) string {
	dockerFile := ctx.Dockerfile()

	// If DOCKER_FILE is set
	if dockerFile != "" {
		// If it's a directory containing ws--Dockerfile, use that file
		wsDockerfile := filepath.Join(dockerFile, "ws--Dockerfile")
		if isDir(dockerFile) && isFile(wsDockerfile) {
			return wsDockerfile
		}
		return dockerFile
	}

	// If DOCKER_FILE is unset, check workspace for ws--Dockerfile
	if ctx.Workspace() != "" {
		wsDockerfile := filepath.Join(ctx.Workspace(), "ws--Dockerfile")
		if isDir(ctx.Workspace()) && isFile(wsDockerfile) {
			return wsDockerfile
		}
	}

	return ""
}

// buildLocalImage builds a local Docker image.
func buildLocalImage(ctx appctx.AppContext) {
	if !ctx.SilenceBuild() {
		fmt.Fprintf(os.Stderr, "Info: building local image '%s' from '%s'...\n",
			ctx.Image(), ctx.Dockerfile())
	}

	if ctx.Verbose() {
		fmt.Println()
		fmt.Printf("Build local image: %s\n", ctx.Image())
		fmt.Printf("  - SILENCE_BUILD: %t\n", ctx.SilenceBuild())
	}

	// Build arguments
	args := []string{
		"-f", ctx.Dockerfile(),
		"-t", ctx.Image(),
		"--build-arg", fmt.Sprintf("WS_VARIANT_TAG=%s", ctx.Variant()),
		"--build-arg", fmt.Sprintf("WS_VERSION_TAG=%s", ctx.Version()),
		"--build-arg", fmt.Sprintf("WS_SETUPS_DIR=%s", ctx.SetupsDir()),
		"--build-arg", fmt.Sprintf("WS_HAS_NOTEBOOK=%t", ctx.HasNotebook()),
		"--build-arg", fmt.Sprintf("WS_HAS_VSCODE=%t", ctx.HasVscode()),
		"--build-arg", fmt.Sprintf("WS_HAS_DESKTOP=%t", ctx.HasDesktop()),
	}

	// Add user's build args
	args = append(args, ctx.BuildArgs().Slice()...)

	// Add context path
	args = append(args, ctx.Workspace())

	// Build the image
	flags := docker.DockerFlags{
		Dryrun:  ctx.Dryrun(),
		Verbose: ctx.Verbose(),
		Silent:  ctx.SilenceBuild(),
	}
	err := docker.DockerBuild(flags, args...)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to build image\n")
		os.Exit(1)
	}
}

// pullImageIfNeeded pulls the Docker image if needed.
func pullImageIfNeeded(ctx appctx.AppContext) {
	imageName := ctx.Image()

	if ctx.Pull() {
		// Always pull when --pull is set
		if !ctx.SilenceBuild() {
			fmt.Fprintf(os.Stderr, "Info: pulling image '%s' (forced by --pull)...\n", imageName)
		}
		if ctx.Verbose() {
			fmt.Printf("Pulling image (forced): %s\n", imageName)
		}

		flags := docker.DockerFlags{
			Dryrun:  ctx.Dryrun(),
			Verbose: ctx.Verbose(),
			Silent:  false,
		}
		err := docker.Docker(flags, "pull", imageName)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: failed to pull '%s'\n", imageName)
			os.Exit(1)
		}

		if ctx.Verbose() {
			fmt.Println()
		}
	} else if !ctx.Dryrun() {
		// Check if image exists locally
		flags := docker.DockerFlags{
			Dryrun:  ctx.Dryrun(),
			Verbose: ctx.Verbose(),
			Silent:  true,
		}
		err := docker.Docker(flags, "image", "inspect", "--format", "{{.Id}}", imageName)
		if err != nil {
			// Image not found locally, pull it
			fmt.Fprintf(os.Stderr, "Info: pulling image '%s' (not found locally)...\n", imageName)
			if ctx.Verbose() {
				fmt.Printf("Image not found locally. Pulling: %s\n", imageName)
			}

			flags := docker.DockerFlags{
				Dryrun:  ctx.Dryrun(),
				Verbose: ctx.Verbose(),
				Silent:  false,
			}
			err = docker.Docker(flags, "pull", imageName)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: failed to pull '%s'\n", imageName)
				os.Exit(1)
			}

			if ctx.Verbose() {
				fmt.Println()
			}
		}
	}
}

// validateImageExists ensures the image exists locally.
func validateImageExists(ctx appctx.AppContext) {
	if ctx.Dryrun() {
		return
	}

	flags := docker.DockerFlags{
		Dryrun:  ctx.Dryrun(),
		Verbose: ctx.Verbose(),
		Silent:  true,
	}
	err := docker.Docker(flags, "image", "inspect", ctx.Image())
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: image '%s' not available locally.\n", ctx.Image())
		fmt.Fprintln(os.Stderr, "       Use '--pull' if you want to force pulling it.")
		os.Exit(1)
	}
}

// isFile checks if a path is a file.
func isFile(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !info.IsDir()
}

// isDir checks if a path is a directory.
func isDir(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return info.IsDir()
}
