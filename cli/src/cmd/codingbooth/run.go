// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"errors"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/booth"
	boothinit "github.com/nawaman/codingbooth/src/pkg/booth/init"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

type runBoundary struct {
	boothinit.DefaultInitializeAppContextBoundary
	args []string
}

func (boundary runBoundary) ArgList() ilist.List[string] {
	return ilist.NewListFromSlice(boundary.args)
}

func runBooth(version string, args []string) {
	// Ignore SIGHUP so the Go binary survives when the container's
	// booth--shutdown/booth--restart sends kill -HUP -1 through the TTY.
	signal.Ignore(syscall.SIGHUP)

	for {
		context := boothinit.InitializeAppContext(version, runBoundary{
			DefaultInitializeAppContextBoundary: boothinit.DefaultInitializeAppContextBoundary{},
			args:                                args,
		})

		if context.Verbose() {
			fmt.Printf("%+v\n", context)
		}

		runner := booth.NewBoothRunner(context)
		err := runner.Run()

		if context.Verbose() {
			fmt.Fprintf(os.Stderr, "[debug] runner.Run() returned: err=%v (type=%T)\n", err, err)
		}

		// Check for restart request
		if _, ok := err.(*booth.RestartRequestedError); ok {
			// Remove the old container if it still exists (keep-alive containers persist)
			removeContainerForRestart(context)
			fmt.Println("🔄 Restarting CodingBooth...")
			continue
		}

		if err != nil {
			// For SilentExitError (from command mode), exit with the code silently
			// Signal-based exits (128+) are normal shutdowns (e.g. booth--shutdown)
			if silentErr, ok := err.(*booth.SilentExitError); ok {
				if context.Verbose() {
					fmt.Fprintf(os.Stderr, "[debug] silent exit: code=%d\n", silentErr.ExitCode)
				}
				if silentErr.ExitCode == 129 {
					os.Exit(0)
					return
				}
				os.Exit(silentErr.ExitCode)
				return
			}
			// Signal-based exits (SIGHUP=129, SIGTERM=143, etc.) are normal shutdowns
			var dockerErr *docker.DockerExitError
			if errors.As(err, &dockerErr) {
				if context.Verbose() {
					fmt.Fprintf(os.Stderr, "[debug] docker exit: code=%d\n", dockerErr.ExitCode)
				}
				if dockerErr.ExitCode == 129 {
					os.Exit(0)
					return
				}
			}
			if context.Verbose() {
				fmt.Fprintf(os.Stderr, "[debug] failing with error: %v\n", err)
			}
			fmt.Println("❌ CodingBooth failed with error:", err)
			os.Exit(1)
			return
		}
		if context.Verbose() {
			fmt.Fprintf(os.Stderr, "[debug] clean exit\n")
		}
		os.Exit(0)
	}
}

// removeContainerForRestart force-removes the container if it still exists.
// Non-keep-alive containers use --rm so they are already gone; keep-alive
// containers persist and must be explicitly removed before restarting.
func removeContainerForRestart(ctx appctx.AppContext) {
	containerName := ctx.Name()
	if containerName == "" {
		containerName = ctx.ProjectName()
	}

	flags := docker.DockerFlags{Silent: true}

	// Check if the container still exists
	output, err := docker.DockerOutput(flags, "ps", ilist.NewList(
		ilist.NewList("-a"),
		ilist.NewList("--filter", "name=^"+containerName+"$"),
		ilist.NewList("--format", "{{.Names}}"),
	))
	if err != nil || strings.TrimSpace(output) == "" {
		return
	}

	// Force remove the container
	_ = docker.Docker(flags, "rm", ilist.NewList(ilist.NewList("-f", containerName)))
}
