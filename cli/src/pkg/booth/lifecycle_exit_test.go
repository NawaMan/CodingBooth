// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"errors"
	"fmt"
	"reflect"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/docker"
)

func TestContainerExitDetails(t *testing.T) {
	cases := []struct {
		name    string
		err     error
		restart bool
		idle    bool
		want    []string
	}{
		{"clean", nil, false, false, []string{"status=0", "by=host-cli"}},
		{"ctrl-c", &docker.DockerExitError{Subcommand: "run", ExitCode: 130}, false, false,
			[]string{"status=130", "signal=SIGINT", "by=host-cli"}},
		{"docker stop", fmt.Errorf("wrapped: %w", &docker.DockerExitError{Subcommand: "run", ExitCode: 143}), false, false,
			[]string{"status=143", "signal=SIGTERM", "by=host-cli"}},
		{"plain failure", &docker.DockerExitError{Subcommand: "run", ExitCode: 3}, false, false,
			[]string{"status=3", "by=host-cli"}},
		{"not a run exit", errors.New("docker: not found"), false, false,
			[]string{`error="docker: not found"`, "by=host-cli"}},
		{"restart", nil, true, false, []string{"status=0", "restart-requested", "by=host-cli"}},
		{"idle", nil, false, true, []string{"status=0", "idle-shutdown", "by=host-cli"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := containerExitDetails(c.err, c.restart, c.idle)
			if !reflect.DeepEqual(got, c.want) {
				t.Errorf("containerExitDetails() = %q, want %q", got, c.want)
			}
		})
	}
}
