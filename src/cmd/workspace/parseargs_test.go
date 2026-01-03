package main

import (
	"testing"

	"github.com/nawaman/workspace/src/pkg/appctx"
)

func TestParseArgs_BooleanFlags(t *testing.T) {
	builder := appctx.NewAppContextBuilder("0.11.0")

	args := []string{"--verbose", "--daemon", "--dryrun", "--pull", "--keep-alive", "--dind", "--silence-build"}
	if err := parseArgs(args, builder); err != nil {
		t.Fatalf("parseArgs failed: %v", err)
	}

	if !builder.Verbose {
		t.Error("Verbose should be true")
	}
	if !builder.Daemon {
		t.Error("Daemon should be true")
	}
	if !builder.Dryrun {
		t.Error("Dryrun should be true")
	}
	if !builder.DoPull {
		t.Error("DoPull should be true")
	}
	if !builder.Keepalive {
		t.Error("Keepalive should be true")
	}
	if !builder.Dind {
		t.Error("Dind should be true")
	}
	if !builder.SilenceBuild {
		t.Error("SilenceBuild should be true")
	}
}

func TestParseArgs_ValueFlags(t *testing.T) {
	builder := appctx.NewAppContextBuilder("0.11.0")

	args := []string{
		"--config", "/path/to/config.toml",
		"--workspace", "/my/workspace",
		"--image", "my/image:tag",
		"--variant", "notebook",
		"--version", "1.2.3",
		"--dockerfile", "/path/to/Dockerfile",
		"--name", "my-container",
		"--port", "9000",
		"--env-file", "/path/to/.env",
	}

	if err := parseArgs(args, builder); err != nil {
		t.Fatalf("parseArgs failed: %v", err)
	}

	if builder.ConfigFile != "/path/to/config.toml" {
		t.Errorf("ConfigFile = %q, want %q", builder.ConfigFile, "/path/to/config.toml")
	}
	if builder.WorkspacePath != "/my/workspace" {
		t.Errorf("WorkspacePath = %q, want %q", builder.WorkspacePath, "/my/workspace")
	}
	if builder.ImageName != "my/image:tag" {
		t.Errorf("ImageName = %q, want %q", builder.ImageName, "my/image:tag")
	}
	if builder.Variant != "notebook" {
		t.Errorf("Variant = %q, want %q", builder.Variant, "notebook")
	}
	if builder.Version != "1.2.3" {
		t.Errorf("Version = %q, want %q", builder.Version, "1.2.3")
	}
	if builder.DockerFile != "/path/to/Dockerfile" {
		t.Errorf("DockerFile = %q, want %q", builder.DockerFile, "/path/to/Dockerfile")
	}
	if builder.ContainerName != "my-container" {
		t.Errorf("ContainerName = %q, want %q", builder.ContainerName, "my-container")
	}
	if builder.WorkspacePort != "9000" {
		t.Errorf("WorkspacePort = %q, want %q", builder.WorkspacePort, "9000")
	}
	if builder.ContainerEnvFile != "/path/to/.env" {
		t.Errorf("ContainerEnvFile = %q, want %q", builder.ContainerEnvFile, "/path/to/.env")
	}
}

func TestParseArgs_BuildArgs(t *testing.T) {
	builder := appctx.NewAppContextBuilder("0.11.0")

	args := []string{
		"--build-arg", "NODE_VERSION=20",
		"--build-arg", "PYTHON_VERSION=3.11",
	}

	if err := parseArgs(args, builder); err != nil {
		t.Fatalf("parseArgs failed: %v", err)
	}

	buildArgs := builder.BuildArgs.Snapshot()
	if buildArgs.Length() != 4 {
		t.Errorf("BuildArgs length = %d, want 4", buildArgs.Length())
	}

	expected := []string{"--build-arg", "NODE_VERSION=20", "--build-arg", "PYTHON_VERSION=3.11"}
	for i, exp := range expected {
		got, ok := buildArgs.Get(i)
		if !ok {
			t.Errorf("BuildArgs.Get(%d) returned false", i)
		}
		if got != exp {
			t.Errorf("BuildArgs[%d] = %q, want %q", i, got, exp)
		}
	}
}

func TestParseArgs_CommandSeparator(t *testing.T) {
	builder := appctx.NewAppContextBuilder("0.11.0")

	args := []string{"--", "bash", "-c", "echo hello"}

	if err := parseArgs(args, builder); err != nil {
		t.Fatalf("parseArgs failed: %v", err)
	}

	cmds := builder.Cmds.Snapshot()
	if cmds.Length() != 3 {
		t.Errorf("Cmds length = %d, want 3", cmds.Length())
	}

	expected := []string{"bash", "-c", "echo hello"}
	for i, exp := range expected {
		got, ok := cmds.Get(i)
		if !ok {
			t.Errorf("Cmds.Get(%d) returned false", i)
		}
		if got != exp {
			t.Errorf("Cmds[%d] = %q, want %q", i, got, exp)
		}
	}
}

func TestParseArgs_RunArgs(t *testing.T) {
	builder := appctx.NewAppContextBuilder("0.11.0")

	args := []string{"-v", "/data:/data", "-e", "FOO=bar"}

	if err := parseArgs(args, builder); err != nil {
		t.Fatalf("parseArgs failed: %v", err)
	}

	runArgs := builder.RunArgs.Snapshot()
	if runArgs.Length() != 4 {
		t.Errorf("RunArgs length = %d, want 4", runArgs.Length())
	}

	expected := []string{"-v", "/data:/data", "-e", "FOO=bar"}
	for i, exp := range expected {
		got, ok := runArgs.Get(i)
		if !ok {
			t.Errorf("RunArgs.Get(%d) returned false", i)
		}
		if got != exp {
			t.Errorf("RunArgs[%d] = %q, want %q", i, got, exp)
		}
	}
}

func TestParseArgs_MixedArgsAndCommands(t *testing.T) {
	builder := appctx.NewAppContextBuilder("0.11.0")

	args := []string{
		"--verbose",
		"--variant", "notebook",
		"-v", "/data:/data",
		"--",
		"ls", "-la",
	}

	if err := parseArgs(args, builder); err != nil {
		t.Fatalf("parseArgs failed: %v", err)
	}

	// Check flags
	if !builder.Verbose {
		t.Error("Verbose should be true")
	}
	if builder.Variant != "notebook" {
		t.Errorf("Variant = %q, want %q", builder.Variant, "notebook")
	}

	// Check run args
	runArgs := builder.RunArgs.Snapshot()
	if runArgs.Length() != 2 {
		t.Errorf("RunArgs length = %d, want 2", runArgs.Length())
	}

	// Check commands
	cmds := builder.Cmds.Snapshot()
	if cmds.Length() != 2 {
		t.Errorf("Cmds length = %d, want 2", cmds.Length())
	}
	expectedCmds := []string{"ls", "-la"}
	for i, exp := range expectedCmds {
		got, ok := cmds.Get(i)
		if !ok {
			t.Errorf("Cmds.Get(%d) returned false", i)
		}
		if got != exp {
			t.Errorf("Cmds[%d] = %q, want %q", i, got, exp)
		}
	}
}

func TestParseArgs_MissingValue(t *testing.T) {
	testCases := []struct {
		name string
		args []string
		want string
	}{
		{"config", []string{"--config"}, "--config requires a path"},
		{"workspace", []string{"--workspace"}, "--workspace requires a path"},
		{"image", []string{"--image"}, "--image requires a value"},
		{"variant", []string{"--variant"}, "--variant requires a value"},
		{"version", []string{"--version"}, "--version requires a value"},
		{"dockerfile", []string{"--dockerfile"}, "--dockerfile requires a path"},
		{"name", []string{"--name"}, "--name requires a value"},
		{"port", []string{"--port"}, "--port requires a value"},
		{"env-file", []string{"--env-file"}, "--env-file requires a path"},
		{"build-arg", []string{"--build-arg"}, "--build-arg requires a value"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			builder := appctx.NewAppContextBuilder("0.11.0")
			err := parseArgs(tc.args, builder)
			if err == nil {
				t.Errorf("Expected error for %v, got nil", tc.args)
			}
			if err.Error() != tc.want {
				t.Errorf("Error = %q, want %q", err.Error(), tc.want)
			}
		})
	}
}

func TestParseArgs_EmptyArgs(t *testing.T) {
	builder := appctx.NewAppContextBuilder("0.11.0")

	if err := parseArgs([]string{}, builder); err != nil {
		t.Fatalf("parseArgs with empty args failed: %v", err)
	}

	// Should have defaults, nothing changed
	if builder.Verbose {
		t.Error("Verbose should be false with no args")
	}
}
