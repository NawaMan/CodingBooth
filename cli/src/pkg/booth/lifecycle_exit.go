// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"errors"
	"strconv"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/lifecyclelog"
)

// exitSignals names the signals a container's exit status most often carries
// (128 + signal number) — what tells "Ctrl+C in the terminal" from "docker kill"
// from "docker stop" once the container is gone.
var exitSignals = map[int]string{
	129: "SIGHUP",
	130: "SIGINT",
	137: "SIGKILL",
	143: "SIGTERM",
}

// logContainerExit records, in the booth's lifecycle log, how a `run` that the
// CLI waited on ended. Only the host sees this: booth-entry execs into the
// booth's main command, so nothing inside is left to note a Ctrl+C or a
// `docker stop`.
func logContainerExit(ctx appctx.AppContext, runErr error, restartRequested bool, idleShutdown bool) {
	if ctx.Dryrun() {
		return
	}
	name := ctx.Name()
	if name == "" {
		name = ctx.ProjectName()
	}
	lifecyclelog.Append(ctx.Code(), name, "exited", containerExitDetails(runErr, restartRequested, idleShutdown)...)
}

// containerExitDetails turns the run's result and the markers the booth left into
// the exit line's details.
func containerExitDetails(runErr error, restartRequested bool, idleShutdown bool) []string {
	details := []string{}
	var exitErr *docker.DockerExitError
	switch {
	case runErr == nil:
		details = append(details, "status=0")
	case errors.As(runErr, &exitErr):
		details = append(details, "status="+strconv.Itoa(exitErr.ExitCode))
		if signal, ok := exitSignals[exitErr.ExitCode]; ok {
			details = append(details, "signal="+signal)
		}
	default:
		details = append(details, "error="+strconv.Quote(runErr.Error()))
	}
	if restartRequested {
		details = append(details, "restart-requested")
	}
	if idleShutdown {
		details = append(details, "idle-shutdown")
	}
	return append(details, "by=host-cli")
}
