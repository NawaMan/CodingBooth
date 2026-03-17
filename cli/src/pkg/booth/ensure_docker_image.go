// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/boothfile"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
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
		dockerFile := NormalizeDockerFile(ctx)
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
			builder.Config.Image = fmt.Sprintf("codingbooth-local:%s-%s-%s",
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

// NormalizeDockerFile normalizes the DOCKER_FILE path, handling Boothfile compilation.
// Returns the Dockerfile path (either existing or generated from Boothfile).
func NormalizeDockerFile(ctx appctx.AppContext) string {
	// If --dockerfile is explicitly set, use it (takes precedence over Boothfile detection)
	if ctx.Dockerfile() != "" {
		dockerFile := ctx.Dockerfile()
		// If it's a directory, check for Dockerfile in .booth/ first
		if isDir(dockerFile) {
			dockerfile := filepath.Join(dockerFile, ".booth", "Dockerfile")
			if isFile(dockerfile) {
				return dockerfile
			}
		}
		return dockerFile
	}

	// If --boothfile is explicitly set, compile it
	if ctx.Boothfile() != "" {
		return compileBoothfile(ctx, ctx.Boothfile())
	}

	// Auto-detect: check code path for Boothfile first, then Dockerfile
	if ctx.Code() != "" && isDir(ctx.Code()) {
		// Check for Boothfile first (higher precedence)
		boothfilePath := filepath.Join(ctx.Code(), ".booth", "Boothfile")
		if isFile(boothfilePath) {
			if ctx.Dockerfile() != "" {
				// Both exist and --dockerfile wasn't explicit - warn
				fmt.Fprintf(os.Stderr, "Warning: Both Boothfile and Dockerfile exist. Using Boothfile.\n")
			}
			return compileBoothfile(ctx, boothfilePath)
		}

		// Fall back to Dockerfile
		dockerfile := filepath.Join(ctx.Code(), ".booth", "Dockerfile")
		if isFile(dockerfile) {
			return dockerfile
		}
	}

	return ""
}

// compileBoothfile compiles a Boothfile to a Dockerfile.
// Returns the path to the generated Dockerfile.
func compileBoothfile(ctx appctx.AppContext, boothfilePath string) string {
	if !ctx.SilenceBuild() {
		fmt.Fprintf(os.Stderr, "Info: compiling Boothfile '%s'...\n", boothfilePath)
	}

	// Read Boothfile
	content, err := os.ReadFile(boothfilePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to read Boothfile '%s': %v\n", boothfilePath, err)
		os.Exit(1)
	}

	// Parse
	parser := boothfile.NewParser()
	if ctx.Strict() {
		parser = boothfile.NewStrictParser()
	}
	parseResult := parser.ParseString(string(content))

	// Check for parse errors
	if parseResult.HasErrors() {
		fmt.Fprintf(os.Stderr, "Error: Boothfile compilation failed:\n")
		for _, e := range parseResult.Errors {
			fmt.Fprintf(os.Stderr, "  %s\n", e.Error())
		}
		os.Exit(1)
	}

	// Show warnings
	if parseResult.HasWarnings() {
		for _, w := range parseResult.Warnings {
			fmt.Fprintf(os.Stderr, "Warning: %s\n", w.Error())
		}
	}

	// Compile with custom setups directory if it exists
	customSetupsDir := filepath.Join(ctx.Code(), ".booth", "setups")
	hasCustomSetups := isDir(customSetupsDir)

	// Scan for custom scripts
	customSetupScripts, customInstallScripts := boothfile.ScanSetupsDir(customSetupsDir)

	// Scan for built-in scripts (if we can find the directory)
	builtinSetupsDir := boothfile.FindBuiltinSetupsDir()
	builtinSetupScripts, builtinInstallScripts := boothfile.ScanSetupsDir(builtinSetupsDir)

	compilerOpts := boothfile.CompilerOptions{
		CustomSetupsDir:      ".booth/setups",
		HasCustomSetups:      hasCustomSetups,
		KnownSetupScripts:    builtinSetupScripts,
		KnownInstallScripts:  builtinInstallScripts,
		CustomSetupScripts:   customSetupScripts,
		CustomInstallScripts: customInstallScripts,
	}
	compiler := boothfile.NewCompilerWithOptions(compilerOpts)
	compileResult := compiler.Compile(parseResult)

	// Check for compile errors
	if compileResult.HasErrors() {
		fmt.Fprintf(os.Stderr, "Error: Boothfile compilation failed:\n")
		for _, e := range compileResult.Errors {
			fmt.Fprintf(os.Stderr, "  %s\n", e.Error())
		}
		os.Exit(1)
	}

	// Handle warnings
	if compileResult.HasWarnings() {
		for _, w := range compileResult.Warnings {
			fmt.Fprintf(os.Stderr, "Warning: %s\n", w.Error())
		}
		// In strict mode, warnings are errors
		if ctx.Strict() {
			fmt.Fprintf(os.Stderr, "Error: Boothfile compilation failed due to warnings (--strict mode)\n")
			os.Exit(1)
		}
	}

	// Write to a temporary file (avoid polluting .booth/)
	tempDir, err := os.MkdirTemp("", "codingbooth-dockerfile-")
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to create temp dir for Dockerfile: %v\n", err)
		os.Exit(1)
	}
	generatedPath := filepath.Join(tempDir, "Dockerfile.generated")
	err = os.WriteFile(generatedPath, []byte(compileResult.Dockerfile), 0644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to write generated Dockerfile: %v\n", err)
		os.Exit(1)
	}

	if ctx.Verbose() {
		fmt.Fprintf(os.Stderr, "Generated Dockerfile: %s\n", generatedPath)
	}

	return generatedPath
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
	args := ilist.NewList[ilist.List[string]]()
	args = args.ExtendByLists(ilist.NewList(ilist.NewList(
		"-f", ctx.Dockerfile(),
		"-t", ctx.Image(),
	)))
	args = args.ExtendByLists(ilist.NewList(ilist.NewList(
		"--build-arg", fmt.Sprintf("BOOTH_VARIANT_TAG=%s", ctx.Variant()),
	)))
	args = args.ExtendByLists(ilist.NewList(ilist.NewList(
		"--build-arg", fmt.Sprintf("BOOTH_VERSION_TAG=%s", ctx.Version()),
	)))
	args = args.ExtendByLists(ilist.NewList(ilist.NewList(
		"--build-arg", fmt.Sprintf("BOOTH_SETUPS=%s", ctx.SetupsDir()),
	)))

	// Add user's build args
	args = args.ExtendByLists(ctx.BuildArgs())

	// Add context path
	args = args.ExtendByLists(ilist.NewList(ilist.NewList(ctx.Code())))

	// Build the image
	flags := docker.DockerFlags{
		Dryrun:  ctx.Dryrun(),
		Verbose: ctx.Verbose(),
		Silent:  ctx.SilenceBuild(),
	}
	err := docker.DockerBuild(flags, args)
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
			Silent:  true,
		}
		err := docker.Docker(flags, "pull", ilist.NewList(ilist.NewList(imageName)))
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
		err := docker.Docker(flags, "image", ilist.NewList(ilist.NewList("inspect", "--format", "{{.Id}}", imageName)))
		if err != nil {
			// Image not found locally, pull it
			fmt.Fprintf(os.Stderr, "Info: pulling image '%s' (not found locally)...\n", imageName)
			if ctx.Verbose() {
				fmt.Printf("Image not found locally. Pulling: %s\n", imageName)
			}

			flags := docker.DockerFlags{
				Dryrun:  ctx.Dryrun(),
				Verbose: ctx.Verbose(),
				Silent:  true,
			}
			err = docker.Docker(flags, "pull", ilist.NewList(ilist.NewList(imageName)))
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
	err := docker.Docker(flags, "image", ilist.NewList(ilist.NewList("inspect", ctx.Image())))
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

