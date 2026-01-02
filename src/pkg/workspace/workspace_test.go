package workspace

import (
	"bytes"
	"io"
	"os"
	"strings"
	"testing"

	"github.com/nawaman/workspace/src/pkg/appctx"
)

// TestWorkspace_runAsCommand_DryrunMode verifies command construction in dryrun mode.
func TestWorkspace_runAsCommand_DryrunMode(t *testing.T) {
	// Capture stdout
	oldStdout := os.Stdout
	reader, writer, _ := os.Pipe()
	os.Stdout = writer

	// Create context with dryrun enabled
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Timezone = "America/New_York"
	builder.ImageName = "test-image:latest"

	// Set up argument lists
	builder.TtyArgs.Append("-it")
	builder.KeepaliveArgs.Append("--rm")
	builder.CommonArgs.Append("--name", "test-container")
	builder.RunArgs.Append("-e", "TEST_VAR=value")
	builder.Cmds.Append("echo 'Hello'", "ls -la")

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Dind = true
	builder.CreatedDindNet = true
	builder.DindName = "test-dind-sidecar"
	builder.DindNet = "test-dind-network"
	builder.Timezone = "UTC"
	builder.ImageName = "alpine:latest"
	builder.Cmds.Append("echo test")

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

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
	if !strings.Contains(output, "test-dind-sidecar") {
		t.Errorf("Expected DinD sidecar name in stop command, got: %q", output)
	}

	// Verify DinD cleanup: docker network rm
	if !strings.Contains(output, "docker network rm") {
		t.Errorf("Expected 'docker network rm' for DinD cleanup, got: %q", output)
	}
	if !strings.Contains(output, "test-dind-network") {
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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Dind = true
	builder.CreatedDindNet = false // Network was not created by us
	builder.DindName = "test-dind-sidecar"
	builder.DindNet = "test-dind-network"
	builder.Timezone = "UTC"
	builder.ImageName = "alpine:latest"
	builder.Cmds.Append("echo test")

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Dind = false
	builder.Timezone = "UTC"
	builder.ImageName = "alpine:latest"
	builder.Cmds.Append("echo test")

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Timezone = "UTC"
	builder.ImageName = "alpine:latest"
	// Don't add any commands to builder.Cmds

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Timezone = "UTC"
	builder.ImageName = "test-image:v1"

	builder.TtyArgs.Append("-it")
	builder.KeepaliveArgs.Append("--rm")
	builder.CommonArgs.Append("--name", "container1")
	builder.RunArgs.Append("-p", "8080:80")
	builder.Cmds.Append("echo hello")

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsCommand()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Timezone = "America/New_York"
	builder.ImageName = "test-image:latest"
	builder.ScriptName = "workspace.sh"
	builder.HostPort = "10000"
	builder.ContainerName = "test-container"

	// Set up argument lists
	builder.KeepaliveArgs.Append("--rm")
	builder.CommonArgs.Append("--name", "test-container")
	builder.RunArgs.Append("-e", "TEST_VAR=value")
	builder.Cmds.Append("echo 'Hello'", "ls -la")

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsDaemon()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsDaemon() in dryrun mode returned error: %v", err)
	}

	// Verify informational messages
	if !strings.Contains(output, "📦 Running workspace in daemon mode.") {
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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Dind = true
	builder.DindName = "test-dind-sidecar"
	builder.DindNet = "test-dind-network"
	builder.Timezone = "UTC"
	builder.ImageName = "alpine:latest"
	builder.ScriptName = "workspace.sh"
	builder.HostPort = "10000"
	builder.ContainerName = "test-container"
	builder.Cmds.Append("echo test")

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsDaemon()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsDaemon() with DinD returned error: %v", err)
	}

	// Verify main docker run command
	if !strings.Contains(output, "docker run") {
		t.Errorf("Expected 'docker run' in output, got: %q", output)
	}

	// Verify DinD informational message (no cleanup in daemon mode)
	if !strings.Contains(output, "🔧 DinD sidecar running: test-dind-sidecar") {
		t.Errorf("Expected DinD sidecar message, got: %q", output)
	}
	if !strings.Contains(output, "docker stop test-dind-sidecar && docker network rm test-dind-network") {
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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Timezone = "UTC"
	builder.ImageName = "alpine:latest"
	builder.ScriptName = "workspace.sh"
	builder.HostPort = "10000"
	builder.ContainerName = "test-container"
	// Don't add any commands

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsDaemon()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

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
	// The word "bash" appears in the help message "workspace.sh -- bash"
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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Keepalive = true
	builder.Timezone = "UTC"
	builder.ImageName = "alpine:latest"
	builder.ScriptName = "workspace.sh"
	builder.HostPort = "10000"
	builder.ContainerName = "test-container"

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsDaemon()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Timezone = "America/New_York"
	builder.ImageName = "test-image:latest"
	builder.ScriptName = "workspace.sh"

	// Set up argument lists
	builder.TtyArgs.Append("-it")
	builder.KeepaliveArgs.Append("--rm")
	builder.CommonArgs.Append("--name", "test-container")
	builder.RunArgs.Append("-e", "TEST_VAR=value")

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsForeground()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

	// Verify no error in dryrun mode
	if err != nil {
		t.Errorf("runAsForeground() in dryrun mode returned error: %v", err)
	}

	// Verify informational messages
	if !strings.Contains(output, "📦 Running workspace in foreground.") {
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
	builder := appctx.NewAppContextBuilder("0.11.0")
	builder.Dryrun = true
	builder.Verbose = true
	builder.Dind = true
	builder.CreatedDindNet = true
	builder.DindName = "test-dind-sidecar"
	builder.DindNet = "test-dind-network"
	builder.Timezone = "UTC"
	builder.ImageName = "alpine:latest"
	builder.ScriptName = "workspace.sh"

	ctx := builder.Build()
	ws := NewWorkspace(ctx)

	// Run the command
	err := ws.runAsForeground()

	// Restore stdout
	writer.Close()
	os.Stdout = oldStdout

	// Read captured output
	var buf bytes.Buffer
	io.Copy(&buf, reader)
	output := buf.String()

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
	if !strings.Contains(output, "test-dind-sidecar") {
		t.Errorf("Expected DinD sidecar name in stop command, got: %q", output)
	}

	// Verify DinD cleanup: docker network rm
	if !strings.Contains(output, "docker network rm") {
		t.Errorf("Expected 'docker network rm' for DinD cleanup, got: %q", output)
	}
	if !strings.Contains(output, "test-dind-network") {
		t.Errorf("Expected DinD network name in rm command, got: %q", output)
	}
}
