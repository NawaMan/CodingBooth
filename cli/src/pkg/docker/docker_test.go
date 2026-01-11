// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"bytes"
	"io"
	"os"
	"strings"
	"testing"

	"github.com/nawaman/workspace/src/pkg/ilist"
)

// TestDocker_DryrunMode verifies no execution in dryrun mode.
func TestDocker_DryrunMode(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with dryrun enabled
	// Define options
	flags := DockerFlags{
		Dryrun:  true,
		Verbose: false,
		Silent:  true,
	}

	// Run docker command (should not execute, just print)
	err := Docker(flags, "version", ilist.NewList(ilist.NewList("--format", "{{.Server.Version}}")))

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

	// Verify no error
	if err != nil {
		t.Errorf("Docker() in dryrun mode returned error: %v", err)
	}

	// Verify command was printed
	if !strings.Contains(output, "docker") {
		t.Errorf("Expected command to be printed in dryrun mode, got: %q", output)
	}
	if !strings.Contains(output, "version") {
		t.Errorf("Expected 'version' in output, got: %q", output)
	}
}

// TestDocker_VerboseMode verifies command printing in verbose mode.
func TestDocker_VerboseMode(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with verbose enabled
	// Define options
	flags := DockerFlags{
		Dryrun:  false,
		Verbose: true,
		Silent:  false,
	}

	// Run docker command
	err := Docker(flags, "version", ilist.NewList(ilist.NewList("--format", "{{.Server.Version}}")))

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

	// Verify no error (docker version should succeed)
	if err != nil {
		t.Logf("Docker version failed (docker may not be installed): %v", err)
		t.Skip("Skipping test - docker not available")
	}

	// Verify command was printed
	if !strings.Contains(output, "docker") {
		t.Errorf("Expected command to be printed in verbose mode, got: %q", output)
	}
}

// TestDocker_Success verifies successful execution.
func TestDocker_Success(t *testing.T) {
	// Create context with no verbose/dryrun
	// Define options
	flags := DockerFlags{
		Dryrun:  false,
		Verbose: false,
		Silent:  false,
	}

	// Run docker version (should succeed if docker is installed)
	err := Docker(flags, "version", ilist.NewList(ilist.NewList("--format", "{{.Server.Version}}")))

	if err != nil {
		t.Logf("Docker version failed (docker may not be installed): %v", err)
		t.Skip("Skipping test - docker not available")
	}
}

// TestDocker_Failure verifies error propagation.
func TestDocker_Failure(t *testing.T) {
	// Create context
	// Define options
	flags := DockerFlags{
		Dryrun:  false,
		Verbose: false,
		Silent:  false,
	}

	// Run invalid docker command (should fail)
	err := Docker(flags, "invalid-subcommand-that-does-not-exist", ilist.NewList[ilist.List[string]]())

	// Verify error is returned
	if err == nil {
		t.Error("Expected error for invalid docker command, got nil")
	}

	// Verify error message contains useful information
	errMsg := err.Error()
	if !strings.Contains(errMsg, "docker") {
		t.Errorf("Expected error message to contain 'docker', got: %q", errMsg)
	}
}

// TestDocker_QuietMode verifies no output in quiet mode (no verbose, no dryrun).
func TestDocker_QuietMode(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with no verbose/dryrun
	// Define options
	flags := DockerFlags{
		Dryrun:  false,
		Verbose: false,
		Silent:  true,
	}

	// Run docker command
	Docker(flags, "version", ilist.NewList(ilist.NewList("--format", "{{.Server.Version}}")))

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

	// In quiet mode, we should only see docker's output, not our command echo
	// The command line itself should NOT be printed
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		// If we see "docker version" as a complete line, that's our echo (bad)
		if strings.TrimSpace(line) == "docker version --format {{.Server.Version}}" {
			t.Errorf("Command should not be echoed in quiet mode, but found: %q", line)
		}
	}
}
