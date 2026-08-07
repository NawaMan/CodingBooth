// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package booth provides the main Booth type for managing Docker-based development environments.
package booth

import (
	"fmt"
	"os"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// BoothRunner handles the "run" command for booth operations.
// It orchestrates the preparation of AppContext and execution of the booth.
type BoothRunner struct {
	ctx appctx.AppContext
}

// NewBoothRunner creates a new BoothRunner with the given AppContext.
func NewBoothRunner(ctx appctx.AppContext) *BoothRunner {
	return &BoothRunner{ctx: ctx}
}

// Run is the main entry point that prepares the context and executes the booth.
func (runner *BoothRunner) Run() error {
	// Prepare arguments and determine run mode (matching booth order)
	ctx := runner.ctx
	SetLogTime(ctx.LogTime())
	ctx = ValidateVariant(ctx)
	ctx = EnsureDockerImage(ctx)
	ctx = PortDetermination(ctx)
	ctx = ResolveNamePlaceholders(ctx)
	// Finalize the container name (and auto-suffix a colliding default) BEFORE the
	// name is consumed: sidecar names (DinD/egress), run args, and the port manifest
	// all read ctx.Name() below, so the final value must be settled here.
	newCtx, err := EnsureContainerName(ctx)
	if err != nil {
		return err
	}
	ctx = newCtx
	ctx = ResolveRelativePorts(ctx)
	ctx = NormalizePortMappings(ctx)
	ctx = ShowDebugBanner(ctx)
	ctx = SetupDind(ctx)
	ctx = SetupEgress(ctx)
	ctx = PrepareRunMode(ctx)
	ctx = PrepareBoothTmp(ctx)
	// WritePortManifest and ApplyEnvFile both run after PrepareBoothTmp so the
	// files they write into .booth/.tmp/ are not wiped by the start-of-run
	// cleanup. WritePortManifest also relies on the port steps above having
	// resolved every mapping to a concrete host port.
	ctx = WritePortManifest(ctx)
	ctx = ApplyEnvFile(ctx)
	ctx = PrepareCommonArgs(ctx)
	// After PrepareCommonArgs so TLS/common mounts are also filtered.
	ctx = FilterMissingVolumeMounts(ctx)
	// Same contract for devices: a template that asks for hardware this host does
	// not have degrades with a warning rather than stopping the booth from starting.
	ctx = FilterMissingDevices(ctx)

	// Create booth with prepared context and run
	booth := NewBooth(ctx)
	return booth.Run(ctx.RunMode())
}

// EnsureContainerName settles the final container name and guarantees it does not
// collide with an existing container.
//
//   - Free name → used as-is.
//   - A taken name that is just the derived project default (the user did not pick
//     a specific one) auto-falls back to "<name>-<port>", so running the same
//     project again does not collide — the port is unique, and the stable base name
//     stays with the first booth. See resolveUniqueName for the decision logic.
//   - A taken name the user chose explicitly is a contract: a collision is an error.
func EnsureContainerName(ctx appctx.AppContext) (appctx.AppContext, error) {
	name := ctx.Name()
	if name == "" {
		name = ctx.ProjectName()
	}

	final, suffixed, err := resolveUniqueName(name, ctx.ProjectName(), ctx.PortNumber(), func(candidate string) (bool, error) {
		return containerNameTaken(ctx, candidate)
	})
	if err != nil {
		return ctx, err
	}
	if suffixed {
		// Informational only, and to stderr so a `booth -- cmd` run keeps stdout clean.
		fmt.Fprintf(os.Stderr, "ℹ️  Booth %q already exists; using %q for this instance.\n", name, final)
	}
	if final == ctx.Name() {
		return ctx, nil
	}
	builder := ctx.ToBuilder()
	builder.Config.Name = final
	return builder.Build(), nil
}

// resolveUniqueName decides the final container name given a taken-ness checker.
// It is pure except for the injected checker, so the decision is unit-testable.
// Returns the chosen name and whether it was auto-suffixed.
func resolveUniqueName(name, projectName string, port int, isTaken func(string) (bool, error)) (string, bool, error) {
	taken, err := isTaken(name)
	if err != nil {
		return "", false, err
	}
	if !taken {
		return name, false, nil
	}

	// Only the derived default name auto-suffixes; an explicit name stays a contract.
	if name == projectName {
		suffixed := fmt.Sprintf("%s-%d", name, port)
		takenToo, err := isTaken(suffixed)
		if err != nil {
			return "", false, err
		}
		if !takenToo {
			return suffixed, true, nil
		}
		return "", false, fmt.Errorf(
			"container names %q and %q both already exist. Choose a name with --name, or remove one with 'booth remove --name %s'",
			name, suffixed, suffixed,
		)
	}

	return "", false, fmt.Errorf(
		"container name %q already exists. Choose a different name with --name, or remove the existing one with 'booth remove --name %s' (or 'docker rm -f %s')",
		name, name, name,
	)
}

// containerNameTaken reports whether a container with the given name already exists.
func containerNameTaken(ctx appctx.AppContext, name string) (bool, error) {
	flags := docker.DockerFlags{
		Dryrun:  ctx.Dryrun(),
		Verbose: ctx.Verbose(),
		Silent:  true,
	}

	output, err := docker.DockerOutput(flags, "ps", ilist.NewList(
		ilist.NewList("-a"),
		ilist.NewList("--filter", "name=^"+name+"$"),
		ilist.NewList("--format", "{{.Names}}"),
	))
	if err != nil {
		return false, fmt.Errorf("failed to check container name availability: %w", err)
	}
	return strings.TrimSpace(output) != "", nil
}

// PrepareRunMode determines the run mode and stores it in the context.
func PrepareRunMode(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	if ctx.Daemon() {
		builder.RunMode = "DAEMON"
	} else if ctx.Cmds().Length() == 0 {
		builder.RunMode = "FOREGROUND"
	} else {
		builder.RunMode = "COMMAND"
	}

	return builder.Build()
}

// SetupDind sets up Docker-in-Docker if enabled and returns updated AppContext.
func SetupDind(ctx appctx.AppContext) appctx.AppContext {
	// Early return if DinD is not enabled
	if !ctx.Dind() {
		return ctx
	}

	builder := ctx.ToBuilder()

	// Clean up any leftover containers/networks from previous booth runs
	// This prevents port conflicts when restarting the booth
	cleanupPreviousBoothInstances(ctx, ctx.ProjectName())

	// Set up unique network and sidecar names
	dindNet := getDindNet(ctx)
	dindName := getDindName(ctx)

	// Create network if it doesn't exist
	createdNet := createDindNetwork(ctx, dindNet)
	builder.CreatedDindNet = createdNet

	// Extract extra port mappings from RunArgs before stripping
	extraPorts := extractPortFlags(ctx.RunArgs())

	// Start DinD sidecar if not already running (pass hostPort for port mapping)
	err := startDindSidecar(ctx, dindName, dindNet, ctx.PortNumber(), extraPorts)
	if err != nil {
		fmt.Fprintf(os.Stderr, "❌ Failed to start DinD sidecar.\n\n")

		// Try to diagnose if this is a port conflict
		port, diagnostic := diagnosePortConflict(err, ctx.PortNumber(), extraPorts)
		if port != "" {
			fmt.Fprintf(os.Stderr, "   %s\n", diagnostic)
		} else {
			// Generic error - show the original error message
			fmt.Fprintf(os.Stderr, "   Error: %v\n", err)
			fmt.Fprintf(os.Stderr, "   Check if any port is already in use.\n")
			fmt.Fprintf(os.Stderr, "   Use 'lsof -i :<port>' or 'ss -tlnp | grep <port>' to find the process.\n")
		}
		os.Exit(1)
	}

	// Wait for DinD to become ready
	waitForDindReady(ctx, dindName, dindNet)

	// Strip network and port flags from RUN_ARGS (not allowed with container network mode)
	builder.RunArgs = stripNetworkAndPortFlags(ctx.RunArgs())

	// Use container network mode to share DinD's network namespace
	// This allows localhost access to DinD's ports from the booth
	builder.CommonArgs.Append(ilist.NewList[string]("--network", fmt.Sprintf("container:%s", dindName)))
	builder.CommonArgs.Append(ilist.NewList[string]("-e", "DOCKER_HOST=tcp://localhost:2375"))

	return builder.Build()
}
