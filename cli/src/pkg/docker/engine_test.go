// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"bytes"
	"os"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func TestDockerFlags_Binary(t *testing.T) {
	tests := []struct {
		name   string
		flags  DockerFlags
		expect string
	}{
		{"empty defaults to docker", DockerFlags{}, "docker"},
		{"explicit docker", DockerFlags{Engine: "docker"}, "docker"},
		{"explicit podman", DockerFlags{Engine: "podman"}, "podman"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.flags.binary(); got != tt.expect {
				t.Errorf("binary() = %q, want %q", got, tt.expect)
			}
		})
	}
}

func TestDocker_DryrunPrintsPodmanBinary(t *testing.T) {
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	flags := DockerFlags{Dryrun: true, Engine: "podman"}
	err := Docker(flags, "ps", ilist.NewList(ilist.NewList("-a")))

	writer.Close()
	os.Stdout = oldStdout

	var buf bytes.Buffer
	buf.ReadFrom(reader)
	output := buf.String()

	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.HasPrefix(output, "podman") {
		t.Errorf("expected dryrun output to start with %q, got %q", "podman", output)
	}
	if strings.Contains(output, "docker") {
		t.Errorf("expected no mention of docker in podman dryrun output, got %q", output)
	}
}

func TestHasBuildKitSupport_NonDockerEngineShortCircuits(t *testing.T) {
	if hasBuildKitSupport("podman") {
		t.Error("hasBuildKitSupport(\"podman\") should always be false; BuildKit is Docker-specific")
	}
}
