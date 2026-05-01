// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/nawaman/codingbooth/src/pkg/booth"
	boothinit "github.com/nawaman/codingbooth/src/pkg/booth/init"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// buildOpts holds the build-specific flags parsed from command-line arguments.
type buildOpts struct {
	pushRegistry string
	name         string
	tag          string
	buildArgs    []string
	code         string
	variant      string
	version      string
	verbose      bool
	dryrun       bool
	silenceBuild bool
}

// parseBuildArgs parses build-specific flags from os.Args[2:].
func parseBuildArgs() buildOpts {
	var opts buildOpts
	args := os.Args[2:]

	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--push":
			if i+1 >= len(args) || args[i+1] == "" {
				fmt.Fprintln(os.Stderr, "Error: --push requires a registry argument")
				os.Exit(1)
			}
			opts.pushRegistry = args[i+1]
			i++
		case "--name":
			if i+1 >= len(args) || args[i+1] == "" {
				fmt.Fprintln(os.Stderr, "Error: --name requires a value")
				os.Exit(1)
			}
			opts.name = args[i+1]
			i++
		case "--tag":
			if i+1 >= len(args) || args[i+1] == "" {
				fmt.Fprintln(os.Stderr, "Error: --tag requires a value")
				os.Exit(1)
			}
			opts.tag = args[i+1]
			i++
		case "--build-arg":
			if i+1 >= len(args) || args[i+1] == "" {
				fmt.Fprintln(os.Stderr, "Error: --build-arg requires a KEY=VALUE argument")
				os.Exit(1)
			}
			opts.buildArgs = append(opts.buildArgs, args[i+1])
			i++
		case "--code":
			if i+1 >= len(args) || args[i+1] == "" {
				fmt.Fprintln(os.Stderr, "Error: --code requires a path argument")
				os.Exit(1)
			}
			opts.code = args[i+1]
			i++
		case "--variant":
			if i+1 >= len(args) || args[i+1] == "" {
				fmt.Fprintln(os.Stderr, "Error: --variant requires a value")
				os.Exit(1)
			}
			opts.variant = args[i+1]
			i++
		case "--version":
			if i+1 >= len(args) || args[i+1] == "" {
				fmt.Fprintln(os.Stderr, "Error: --version requires a value")
				os.Exit(1)
			}
			opts.version = args[i+1]
			i++
		case "--verbose":
			opts.verbose = true
		case "--dryrun":
			opts.dryrun = true
		case "--silence-build":
			opts.silenceBuild = true
		default:
			fmt.Fprintf(os.Stderr, "Error: unknown flag for build: %s\n", args[i])
			fmt.Fprintln(os.Stderr, "Usage: booth build [--push <registry>] [--name <name>] [--tag <tag>] [--build-arg KEY=VALUE ...] [--code <path>] [--variant <variant>] [--version <version>] [--verbose] [--dryrun]")
			os.Exit(1)
		}
	}

	return opts
}

// buildBooth implements the "booth build" command.
func buildBooth(version string) {
	opts := parseBuildArgs()

	// Build the run args to pass through to InitializeAppContext.
	// We construct a minimal arg list with only the flags that affect image building.
	var runArgs []string
	runArgs = append(runArgs, os.Args[0]) // program name
	if opts.code != "" {
		runArgs = append(runArgs, "--code", opts.code)
	}
	if opts.variant != "" {
		runArgs = append(runArgs, "--variant", opts.variant)
	}
	if opts.version != "" {
		runArgs = append(runArgs, "--version", opts.version)
	}
	if opts.verbose {
		runArgs = append(runArgs, "--verbose")
	}
	if opts.dryrun {
		runArgs = append(runArgs, "--dryrun")
	}
	if opts.silenceBuild {
		runArgs = append(runArgs, "--silence-build")
	}
	for _, ba := range opts.buildArgs {
		runArgs = append(runArgs, "--build-arg", ba)
	}

	// Initialize context to get config values (variant, version, build-args from config.toml)
	ctx := initOrExit(version, buildBoundary{
		boothinit.DefaultInitializeAppContextBoundary{},
		runArgs,
	})

	// Resolve the Boothfile content for hashing
	codePath := ctx.Code()
	if codePath == "" {
		codePath = "."
	}
	boothfilePath := filepath.Join(codePath, ".booth", "Boothfile")
	boothfileContent := ""
	if info, err := os.Stat(boothfilePath); err == nil && !info.IsDir() {
		data, err := os.ReadFile(boothfilePath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: failed to read Boothfile '%s': %v\n", boothfilePath, err)
			os.Exit(1)
		}
		boothfileContent = string(data)
	}

	// Collect all build-args for hashing (config + CLI)
	var allBuildArgs []string
	ctx.BuildArgs().Range(func(_ int, group ilist.List[string]) bool {
		group.Range(func(_ int, arg string) bool {
			allBuildArgs = append(allBuildArgs, arg)
			return true
		})
		return true
	})

	// Resolve name
	name := opts.name
	if name == "" {
		name = ctx.Name()
		if name == "" {
			name = ctx.ProjectName()
		}
	}

	// Resolve tag
	tag := opts.tag
	if tag == "" {
		tag = booth.ComputeBuildHash(boothfileContent, allBuildArgs, ctx.Variant(), ctx.Version())
	}

	// Assemble image name
	imageName := booth.AssembleImageName(opts.pushRegistry, name, tag)

	if ctx.Verbose() {
		fmt.Fprintf(os.Stderr, "Build target: %s\n", imageName)
		fmt.Fprintf(os.Stderr, "  Registry:   %q\n", opts.pushRegistry)
		fmt.Fprintf(os.Stderr, "  Name:       %q\n", name)
		fmt.Fprintf(os.Stderr, "  Tag:        %q\n", tag)
		fmt.Fprintf(os.Stderr, "  Variant:    %q\n", ctx.Variant())
		fmt.Fprintf(os.Stderr, "  Version:    %q\n", ctx.Version())
	}

	// Resolve the Dockerfile (compile Boothfile if needed)
	dockerfilePath := booth.NormalizeDockerFile(ctx)
	if dockerfilePath == "" {
		fmt.Fprintln(os.Stderr, "Error: no Boothfile or Dockerfile found. Cannot build.")
		os.Exit(1)
	}

	// Build the docker args
	args := ilist.NewList[ilist.List[string]]()
	args = args.ExtendByLists(ilist.NewList(ilist.NewList(
		"-f", dockerfilePath,
		"-t", imageName,
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
	args = args.ExtendByLists(ilist.NewList(ilist.NewList(codePath)))

	flags := docker.DockerFlags{
		Dryrun:  ctx.Dryrun(),
		Verbose: ctx.Verbose(),
		Silent:  ctx.SilenceBuild(),
	}

	if opts.pushRegistry != "" {
		// Build locally then push to registry
		if !ctx.SilenceBuild() {
			fmt.Fprintf(os.Stderr, "Building and pushing '%s'...\n", imageName)
		}

		err := docker.DockerBuildAndPush(flags, args, imageName)
		if err != nil {
			host := booth.ExtractRegistryHost(opts.pushRegistry)
			fmt.Fprintf(os.Stderr, "\nError: push to %s failed.\n", imageName)
			fmt.Fprintf(os.Stderr, "  Ensure you are logged in: docker login %s\n", host)
			os.Exit(1)
		}

		fmt.Printf("Pushed: %s\n", imageName)
	} else {
		// Local build only
		if !ctx.SilenceBuild() {
			fmt.Fprintf(os.Stderr, "Building '%s'...\n", imageName)
		}

		err := docker.DockerBuild(flags, args)
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error: build failed.")
			os.Exit(1)
		}

		fmt.Printf("Built: %s\n", imageName)
	}
}

// buildBoundary implements InitializeAppContextBoundary for the build command.
type buildBoundary struct {
	boothinit.DefaultInitializeAppContextBoundary
	args []string
}

func (b buildBoundary) ArgList() ilist.List[string] {
	return ilist.NewListFromSlice(b.args)
}
