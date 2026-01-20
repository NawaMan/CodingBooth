// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/nawaman/coding-booth/src/pkg/appctx"
	"github.com/nawaman/coding-booth/src/pkg/ilist"
	"github.com/nawaman/coding-booth/src/pkg/nillable"
)

// getTestVersion reads the version from version.txt at the project root.
func getTestVersion() string {
	_, currentFile, _, _ := runtime.Caller(0)
	// Navigate from cli/src/pkg/booth/booth_test.go to project root
	projectRoot := filepath.Join(filepath.Dir(currentFile), "..", "..", "..", "..")
	versionFile := filepath.Join(projectRoot, "version.txt")
	data, err := os.ReadFile(versionFile)
	if err != nil {
		panic("failed to read version.txt: " + err.Error())
	}
	return strings.TrimSpace(string(data))
}

// TestWorkspace_runAsCommand_DryrunMode verifies command construction in dryrun mode.
func TestWorkspace_runAsCommand_DryrunMode(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with dryrun enabled
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Timezone = "America/New_York"
	builder.Config.Image = "test-image:latest"

	// Set up argument lists
	builder.CommonArgs.Append(ilist.NewList("--name", "test-container"))
	builder.RunArgs.Append(ilist.NewList("-e", "TEST_VAR=value"))
	builder.Cmds.Append(ilist.NewList("echo", "Hello"), ilist.NewList("ls", "-la"))

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsCommand() in dryrun mode returned error: %v", err)
	}

	// Verify command was printed
	if !strings.Contains(output, "docker") {
		t.Errorf("Expected 'docker' in output, got: %q", output)
	}
	if !strings.Contains(output, "run") {
		t.Errorf("Expected 'run' in output, got: %q", output)
	}

	// Verify TTY args are managed by Docker function (user-provided -it is filtered)
	// The Docker function adds -i automatically for run commands
	if !strings.Contains(output, "-i") {
		t.Errorf("Expected '-i' in output, got: %q", output)
	}

	// Verify keepalive args are included
	if !strings.Contains(output, "--rm") {
		t.Errorf("Expected '--rm' in output, got: %q", output)
	}

	// Verify common args are included
	if !strings.Contains(output, "test-container") {
		t.Errorf("Expected 'test-container' in output, got: %q", output)
	}

	// Verify run args are included
	if !strings.Contains(output, "TEST_VAR=value") {
		t.Errorf("Expected 'TEST_VAR=value' in output, got: %q", output)
	}

	// Verify timezone is included
	if !strings.Contains(output, "TZ=America/New_York") {
		t.Errorf("Expected 'TZ=America/New_York' in output, got: %q", output)
	}

	// Verify image name is included
	if !strings.Contains(output, "test-image:latest") {
		t.Errorf("Expected 'test-image:latest' in output, got: %q", output)
	}

	// Verify bash -lc wrapper is applied
	if !strings.Contains(output, "bash") {
		t.Errorf("Expected 'bash' in output, got: %q", output)
	}
	if !strings.Contains(output, "-lc") {
		t.Errorf("Expected '-lc' in output, got: %q", output)
	}

	// Verify user commands are joined (note: quotes may be escaped in output)
	if !strings.Contains(output, "echo") || !strings.Contains(output, "ls -la") {
		t.Errorf("Expected user commands in output, got: %q", output)
	}
}

// TestWorkspace_runAsCommand_WithDind verifies DinD cleanup logic.
func TestWorkspace_runAsCommand_WithDind(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with DinD enabled
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Dind = true
	builder.CreatedDindNet = true
	builder.Config.Name = "test-container"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.Config.Timezone = "UTC"
	builder.Config.Image = "alpine:latest"
	builder.Cmds.Append(ilist.NewList("echo", "test"))

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsCommand() with DinD returned error: %v", err)
	}

	// Verify main docker run command
	if !strings.Contains(output, "docker run") {
		t.Errorf("Expected 'docker run' in output, got: %q", output)
	}

	// Verify DinD cleanup: docker stop
	if !strings.Contains(output, "docker stop") {
		t.Errorf("Expected 'docker stop' for DinD cleanup, got: %q", output)
	}
	if !strings.Contains(output, "test-container-10000-dind") {
		t.Errorf("Expected DinD sidecar name in stop command, got: %q", output)
	}

	// Verify DinD cleanup: docker network rm
	if !strings.Contains(output, "docker network rm") {
		t.Errorf("Expected 'docker network rm' for DinD cleanup, got: %q", output)
	}
	if !strings.Contains(output, "test-container-10000-net") {
		t.Errorf("Expected DinD network name in rm command, got: %q", output)
	}
}

// TestWorkspace_runAsCommand_WithDindNoNetwork verifies DinD cleanup without network removal.
func TestWorkspace_runAsCommand_WithDindNoNetwork(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with DinD enabled but CreatedDindNet=false
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Dind = true
	builder.CreatedDindNet = false // Network was not created by us
	builder.Config.Name = "test-container"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.Config.Timezone = "UTC"
	builder.Config.Image = "alpine:latest"
	builder.Cmds.Append(ilist.NewList("echo", "test"))

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsCommand() with DinD returned error: %v", err)
	}

	// Verify main docker run command
	if !strings.Contains(output, "docker run") {
		t.Errorf("Expected 'docker run' in output, got: %q", output)
	}

	// Verify DinD cleanup: docker stop (should still happen)
	if !strings.Contains(output, "docker stop") {
		t.Errorf("Expected 'docker stop' for DinD cleanup, got: %q", output)
	}

	// Verify DinD cleanup: docker network rm should NOT happen
	if strings.Contains(output, "docker network rm") {
		t.Errorf("Did not expect 'docker network rm' when CreatedDindNet=false, got: %q", output)
	}
}

// TestWorkspace_runAsCommand_WithoutDind verifies no cleanup when DinD is disabled.
func TestWorkspace_runAsCommand_WithoutDind(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with DinD disabled
	// Create context with DinD disabled
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Dind = false
	builder.Config.Timezone = "UTC"
	builder.Config.Image = "alpine:latest"
	builder.Cmds.Append(ilist.NewList("echo", "test"))

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsCommand() without DinD returned error: %v", err)
	}

	// Verify main docker run command
	if !strings.Contains(output, "docker run") {
		t.Errorf("Expected 'docker run' in output, got: %q", output)
	}

	// Count occurrences of "docker" - should only be the main run command
	dockerCount := strings.Count(output, "docker")
	if dockerCount != 1 {
		t.Errorf("Expected exactly 1 'docker' command (no cleanup), got %d occurrences in: %q", dockerCount, output)
	}

	// Verify no stop command
	if strings.Contains(output, "docker stop") {
		t.Errorf("Did not expect 'docker stop' when DinD disabled, got: %q", output)
	}

	// Verify no network rm command
	if strings.Contains(output, "docker network rm") {
		t.Errorf("Did not expect 'docker network rm' when DinD disabled, got: %q", output)
	}
}

// TestWorkspace_runAsCommand_EmptyCommands verifies handling of empty command list.
func TestWorkspace_runAsCommand_EmptyCommands(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with no commands
	// Create context with no commands
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Timezone = "UTC"
	builder.Config.Image = "alpine:latest"
	// Don't add any commands to builder.Cmds

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsCommand() with empty commands returned error: %v", err)
	}

	// Verify bash -lc is still present with empty string
	if !strings.Contains(output, "bash") {
		t.Errorf("Expected 'bash' in output, got: %q", output)
	}
	if !strings.Contains(output, "-lc") {
		t.Errorf("Expected '-lc' in output, got: %q", output)
	}
}

// TestWorkspace_runAsCommand_ArgumentOrder verifies the order of arguments.
func TestWorkspace_runAsCommand_ArgumentOrder(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with all argument types
	// Create context with all argument types
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Timezone = "UTC"
	builder.Config.Image = "test-image:v1"

	builder.CommonArgs.Append(ilist.NewList("--name", "container1"))
	builder.RunArgs.Append(ilist.NewList("-p", "8080:80"))
	builder.Cmds.Append(ilist.NewList("echo", "hello"))

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error
	if err != nil {
		t.Errorf("runAsCommand() returned error: %v", err)
	}

	// Find positions of key elements to verify order
	// Expected order: docker run [auto-added -i] [keepalive] [common] [run] -e TZ=... image bash -lc "..."
	// Note: -it from TtyArgs is filtered by Docker function, which adds -i automatically
	posRun := strings.Index(output, "run")
	posTtyI := strings.Index(output, "-i") // Docker adds -i automatically
	posRm := strings.Index(output, "--rm")
	posName := strings.Index(output, "--name")
	posPort := strings.Index(output, "-p")
	posTZ := strings.Index(output, "TZ=")
	posImage := strings.Index(output, "test-image:v1")
	posBash := strings.Index(output, "bash")

	// Verify order: run < -i < rm < name < port < TZ < image < bash
	if !(posRun < posTtyI && posTtyI < posRm && posRm < posName && posName < posPort && posPort < posTZ && posTZ < posImage && posImage < posBash) {
		t.Errorf("Arguments are not in expected order. Output: %q", output)
		t.Logf("Positions: run=%d, -i=%d, rm=%d, name=%d, port=%d, TZ=%d, image=%d, bash=%d",
			posRun, posTtyI, posRm, posName, posPort, posTZ, posImage, posBash)
	}
}

// TestWorkspace_runAsDaemon_DryrunMode verifies daemon mode command construction.
func TestWorkspace_runAsDaemon_DryrunMode(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with dryrun enabled
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Timezone = "America/New_York"
	builder.Config.Image = "test-image:latest"
	builder.Config.Name = "test-container"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.PortNumber = 10000
	// Set up argument lists
	builder.CommonArgs.Append(ilist.NewList("--name", "test-container"))
	builder.RunArgs.Append(ilist.NewList("-e", "TEST_VAR=value"))
	builder.Cmds.Append(ilist.NewList("echo", "Hello"), ilist.NewList("ls", "-la"))

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsDaemon()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsDaemon() in dryrun mode returned error: %v", err)
	}

	// Verify informational messages
	if !strings.Contains(output, "📦 Running booth in daemon mode.") {
		t.Errorf("Expected daemon mode message, got: %q", output)
	}

	if !strings.Contains(output, "http://localhost:10000") {
		t.Errorf("Expected port message, got: %q", output)
	}

	if !strings.Contains(output, "Container Name: test-container") {
		t.Errorf("Expected container name message, got: %q", output)
	}

	if !strings.Contains(output, "<--dryrun-->") {
		t.Errorf("Expected dryrun message, got: %q", output)
	}

	// Verify docker command was printed
	if !strings.Contains(output, "docker") {
		t.Errorf("Expected 'docker' in output, got: %q", output)
	}
	if !strings.Contains(output, "run") {
		t.Errorf("Expected 'run' in output, got: %q", output)
	}

	// Verify -d flag for daemon mode
	if !strings.Contains(output, "-d") {
		t.Errorf("Expected '-d' flag for daemon mode, got: %q", output)
	}

	// Verify keepalive args are included
	if !strings.Contains(output, "--rm") {
		t.Errorf("Expected '--rm' in output, got: %q", output)
	}

	// Verify timezone is included
	if !strings.Contains(output, "TZ=America/New_York") {
		t.Errorf("Expected 'TZ=America/New_York' in output, got: %q", output)
	}

	// Verify image name is included
	if !strings.Contains(output, "test-image:latest") {
		t.Errorf("Expected 'test-image:latest' in output, got: %q", output)
	}

	// Verify bash -lc wrapper for commands
	if !strings.Contains(output, "bash") {
		t.Errorf("Expected 'bash' in output, got: %q", output)
	}
	if !strings.Contains(output, "-lc") {
		t.Errorf("Expected '-lc' in output, got: %q", output)
	}
}

// TestWorkspace_runAsDaemon_WithDind verifies DinD informational message.
func TestWorkspace_runAsDaemon_WithDind(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with DinD enabled
	// Create context with DinD enabled
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Dind = true
	builder.Config.Name = "test-container"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000

	// DindName/DindNet derived from name/port
	builder.Config.Timezone = "UTC"
	builder.Config.Image = "alpine:latest"
	builder.ScriptName = "workspace"
	builder.Cmds.Append(ilist.NewList("echo", "test"))

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsDaemon()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsDaemon() with DinD returned error: %v", err)
	}

	// Verify main docker run command
	if !strings.Contains(output, "docker run") {
		t.Errorf("Expected 'docker run' in output, got: %q", output)
	}

	// Verify DinD informational message (no cleanup in daemon mode)
	if !strings.Contains(output, "🔧 DinD sidecar running: test-container-10000-dind") {
		t.Errorf("Expected DinD sidecar message, got: %q", output)
	}
	if !strings.Contains(output, "docker stop test-container-10000-dind && docker network rm test-container-10000-net") {
		t.Errorf("Expected DinD stop instructions, got: %q", output)
	}
}

// TestWorkspace_runAsDaemon_NoCommands verifies daemon mode without commands.
func TestWorkspace_runAsDaemon_NoCommands(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with no commands
	// Create context with no commands
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Timezone = "UTC"
	builder.Config.Image = "alpine:latest"
	builder.ScriptName = "workspace"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.Config.Name = "test-container"
	// Don't add any commands

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsDaemon()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsDaemon() without commands returned error: %v", err)
	}

	// Verify docker run command
	if !strings.Contains(output, "docker run") {
		t.Errorf("Expected 'docker run' in output, got: %q", output)
	}

	// Verify -d flag
	if !strings.Contains(output, "-d") {
		t.Errorf("Expected '-d' flag, got: %q", output)
	}

	// Should NOT have bash -lc when no commands
	// The word "bash" appears in the help message "workspace -- bash"
	// but should not appear as a command argument after the image name
	// Check that the docker command doesn't have bash after the image name
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "docker run") {
			// This is the docker command line
			// It should have the image but not bash as a command
			if strings.Contains(line, "alpine:latest bash") {
				t.Errorf("Did not expect 'bash' command when no commands provided, got: %q", line)
			}
		}
	}
}

// TestWorkspace_runAsDaemon_WithKeepalive verifies keepalive mode messaging.
func TestWorkspace_runAsDaemon_WithKeepalive(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with keepalive enabled
	// Create context with keepalive enabled
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.KeepAlive = true
	builder.Config.Timezone = "UTC"
	builder.Config.Image = "alpine:latest"
	builder.ScriptName = "workspace"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.Config.Name = "test-container"

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsDaemon()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error
	if err != nil {
		t.Errorf("runAsDaemon() with keepalive returned error: %v", err)
	}

	// Should NOT show the --rm message when keepalive is true
	if strings.Contains(output, "will be removed (--rm)") {
		t.Errorf("Did not expect --rm message when keepalive=true, got: %q", output)
	}
}

// TestWorkspace_runAsForeground_DryrunMode verifies foreground mode command construction.
func TestWorkspace_runAsForeground_DryrunMode(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with dryrun enabled
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Timezone = "America/New_York"
	builder.Config.Image = "test-image:latest"
	builder.Config.Name = "test-container"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.ScriptName = "workspace"

	// Set up argument lists
	builder.CommonArgs.Append(ilist.NewList("--name", "test-container"))
	builder.RunArgs.Append(ilist.NewList("-e", "TEST_VAR=value"))

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsForeground()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsForeground() in dryrun mode returned error: %v", err)
	}

	// Verify informational messages
	if !strings.Contains(output, "📦 Running booth in foreground.") {
		t.Errorf("Expected foreground mode message, got: %q", output)
	}

	if !strings.Contains(output, "Stop with Ctrl+C") {
		t.Errorf("Expected Ctrl+C message, got: %q", output)
	}

	// Verify docker command was printed
	if !strings.Contains(output, "docker") {
		t.Errorf("Expected 'docker' in output, got: %q", output)
	}
	if !strings.Contains(output, "run") {
		t.Errorf("Expected 'run' in output, got: %q", output)
	}

	// Should NOT have -d flag (foreground mode)
	if strings.Contains(output, " -d ") {
		t.Errorf("Did not expect '-d' flag in foreground mode, got: %q", output)
	}

	// Verify TTY args are managed by Docker function
	if !strings.Contains(output, "-i") {
		t.Errorf("Expected '-i' in output, got: %q", output)
	}

	// Verify keepalive args are included
	if !strings.Contains(output, "--rm") {
		t.Errorf("Expected '--rm' in output, got: %q", output)
	}

	// Verify timezone is included
	if !strings.Contains(output, "TZ=America/New_York") {
		t.Errorf("Expected 'TZ=America/New_York' in output, got: %q", output)
	}

	// Verify image name is included
	if !strings.Contains(output, "test-image:latest") {
		t.Errorf("Expected 'test-image:latest' in output, got: %q", output)
	}
}

// TestWorkspace_runAsForeground_WithDind verifies DinD cleanup logic.
func TestWorkspace_runAsForeground_WithDind(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with DinD enabled
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Dind = true
	builder.CreatedDindNet = true
	builder.Config.Name = "test-container"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.Config.Timezone = "UTC"
	builder.Config.Image = "alpine:latest"
	builder.ScriptName = "workspace"

	ctx := builder.Build()
	ws := NewBooth(ctx)

	// Run the command
	err := ws.runAsForeground()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsForeground() with DinD returned error: %v", err)
	}

	// Verify main docker run command
	if !strings.Contains(output, "docker run") {
		t.Errorf("Expected 'docker run' in output, got: %q", output)
	}

	// Verify DinD cleanup: docker stop
	if !strings.Contains(output, "docker stop") {
		t.Errorf("Expected 'docker stop' for DinD cleanup, got: %q", output)
	}
	if !strings.Contains(output, "test-container-10000-dind") {
		t.Errorf("Expected DinD sidecar name in stop command, got: %q", output)
	}

	// Verify DinD cleanup: docker network rm
	if !strings.Contains(output, "docker network rm") {
		t.Errorf("Expected 'docker network rm' for DinD cleanup, got: %q", output)
	}
	if !strings.Contains(output, "test-container-10000-net") {
		t.Errorf("Expected DinD network name in rm command, got: %q", output)
	}
}

// TestWorkspace_Run_DaemonMode verifies Run delegates to runAsDaemon when daemon flag is set.
func TestWorkspace_Run_DaemonMode(t *testing.T) {
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with daemon enabled
	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Daemon = true
	builder.Config.Timezone = "UTC"
	builder.Config.Image = "alpine:latest"
	builder.Config.Variant = "base"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.Config.Name = "test-container"
	builder.ScriptName = "workspace"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.Config.Name = "test-container"
	builder.Cmds.Append(ilist.NewList("echo", "test"))

	ctx := builder.Build()
	runner := NewBoothRunner(ctx)

	err := runner.Run()

	writer.Close()
	os.Stdout = oldStdout

	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	if err != nil {
		t.Errorf("Run() in daemon mode returned error: %v", err)
	}

	// Should see daemon mode message
	if !strings.Contains(output, "📦 Running booth in daemon mode.") {
		t.Errorf("Expected daemon mode message, got: %q", output)
	}

	// Should have -d flag
	if !strings.Contains(output, "-d") {
		t.Errorf("Expected '-d' flag for daemon mode, got: %q", output)
	}
}

// TestWorkspace_Run_ForegroundMode verifies Run delegates to runAsForeground when no commands.
func TestWorkspace_Run_ForegroundMode(t *testing.T) {
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Daemon = false
	builder.Config.Timezone = "UTC"
	builder.Config.Variant = "base"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.Config.Name = "test-container"
	builder.Config.Image = "alpine:latest"
	builder.ScriptName = "workspace"
	// No commands - should trigger foreground mode

	ctx := builder.Build()
	runner := NewBoothRunner(ctx)

	err := runner.Run()

	writer.Close()
	os.Stdout = oldStdout

	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	if err != nil {
		t.Errorf("Run() in foreground mode returned error: %v", err)
	}

	// Should see foreground mode message
	if !strings.Contains(output, "📦 Running booth in foreground.") {
		t.Errorf("Expected foreground mode message, got: %q", output)
	}

	// Should NOT have -d flag
	if strings.Contains(output, " -d ") {
		t.Errorf("Did not expect '-d' flag in foreground mode, got: %q", output)
	}
}

// TestWorkspace_Run_CommandMode verifies Run delegates to runAsCommand when commands are provided.
func TestWorkspace_Run_CommandMode(t *testing.T) {
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	builder := &appctx.AppContextBuilder{
		CbVersion:  getTestVersion(),
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Dryrun = nillable.NewNillableBool(true)
	builder.Config.Verbose = nillable.NewNillableBool(true)
	builder.Config.Daemon = false
	builder.Config.Timezone = "UTC"
	builder.Config.Variant = "base"
	builder.Config.Port = "10000"
	builder.PortNumber = 10000
	builder.Config.Name = "test-container"
	builder.Config.Image = "alpine:latest"
	builder.Cmds.Append(ilist.NewList("echo", "hello"), ilist.NewList("ls", "-la"))

	ctx := builder.Build()
	runner := NewBoothRunner(ctx)

	err := runner.Run()

	writer.Close()
	os.Stdout = oldStdout

	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := normalizeOutput(buf.String())

	if err != nil {
		t.Errorf("Run() in command mode returned error: %v", err)
	}

	// Should have bash -lc wrapper (command mode)
	if !strings.Contains(output, "bash") {
		t.Errorf("Expected 'bash' in command mode, got: %q", output)
	}
	if !strings.Contains(output, "-lc") {
		t.Errorf("Expected '-lc' in command mode, got: %q", output)
	}

	// Should NOT have -d flag
	if strings.Contains(output, " -d ") {
		t.Errorf("Did not expect '-d' flag in command mode, got: %q", output)
	}
}

func normalizeOutput(s string) string {
	return strings.ReplaceAll(s, " \\\n    ", " ")
}
