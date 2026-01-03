package appctx

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/BurntSushi/toml"
)

func TestAppContextBuilder_TOMLDecoding(t *testing.T) {
	// Create a temporary directory for test files
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "test-config.toml")

	// Write a test TOML config
	configContent := `
# Test configuration
Variant = "notebook"
Version = "1.2.3"
Daemon = true
Verbose = true
WorkspacePort = "8080"
ContainerName = "test-container"

# Array fields
RunArgs = ["-v", "/data:/data", "-e", "TEST=value"]
BuildArgs = ["--build-arg", "NODE_VERSION=20"]
CommonArgs = ["--test", "arg"]
`

	if err := os.WriteFile(configFile, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	// Create a builder with defaults
	builder := NewAppContextBuilder("0.11.0")

	// Decode TOML into builder
	if _, err := toml.DecodeFile(configFile, builder); err != nil {
		t.Fatalf("Failed to decode TOML: %v", err)
	}

	// Apply slices to lists
	builder.ApplySlicesToLists()

	// Verify scalar fields
	if builder.Variant != "notebook" {
		t.Errorf("Variant = %q, want %q", builder.Variant, "notebook")
	}
	if builder.Version != "1.2.3" {
		t.Errorf("Version = %q, want %q", builder.Version, "1.2.3")
	}
	if !builder.Daemon {
		t.Error("Daemon = false, want true")
	}
	if !builder.Verbose {
		t.Error("Verbose = false, want true")
	}
	if builder.WorkspacePort != "8080" {
		t.Errorf("WorkspacePort = %q, want %q", builder.WorkspacePort, "8080")
	}
	if builder.ContainerName != "test-container" {
		t.Errorf("ContainerName = %q, want %q", builder.ContainerName, "test-container")
	}

	// Verify array fields were converted to AppendableList
	runArgs := builder.RunArgs.Snapshot()
	if runArgs.Length() != 4 {
		t.Errorf("RunArgs length = %d, want 4", runArgs.Length())
	}
	expectedRunArgs := []string{"-v", "/data:/data", "-e", "TEST=value"}
	for i, expected := range expectedRunArgs {
		got, ok := runArgs.Get(i)
		if !ok {
			t.Errorf("RunArgs.Get(%d) returned false", i)
		}
		if got != expected {
			t.Errorf("RunArgs[%d] = %q, want %q", i, got, expected)
		}
	}

	buildArgs := builder.BuildArgs.Snapshot()
	if buildArgs.Length() != 2 {
		t.Errorf("BuildArgs length = %d, want 2", buildArgs.Length())
	}

	commonArgs := builder.CommonArgs.Snapshot()
	if commonArgs.Length() != 2 {
		t.Errorf("CommonArgs length = %d, want 2", commonArgs.Length())
	}
}

func TestAppContextBuilder_TOMLDefaults(t *testing.T) {
	// Create a builder with defaults
	builder := NewAppContextBuilder("0.11.0")

	// Create a minimal TOML config that only sets one field
	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "minimal-config.toml")
	configContent := `Variant = "codeserver"`

	if err := os.WriteFile(configFile, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	// Decode TOML
	if _, err := toml.DecodeFile(configFile, builder); err != nil {
		t.Fatalf("Failed to decode TOML: %v", err)
	}

	// Verify the TOML field was set
	if builder.Variant != "codeserver" {
		t.Errorf("Variant = %q, want %q", builder.Variant, "codeserver")
	}

	// Verify defaults are still intact
	if builder.PrebuildRepo != "nawaman/workspace" {
		t.Errorf("PrebuildRepo = %q, want %q", builder.PrebuildRepo, "nawaman/workspace")
	}
	if builder.SetupsDir != "/opt/workspace/setups" {
		t.Errorf("SetupsDir = %q, want %q", builder.SetupsDir, "/opt/workspace/setups")
	}
	if builder.WorkspacePort != "NEXT" {
		t.Errorf("WorkspacePort = %q, want %q", builder.WorkspacePort, "NEXT")
	}
}

func TestAppContextBuilder_TOMLEmptyArrays(t *testing.T) {
	builder := NewAppContextBuilder("0.11.0")

	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "empty-arrays.toml")
	configContent := `
Variant = "base"
RunArgs = []
BuildArgs = []
`

	if err := os.WriteFile(configFile, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	if _, err := toml.DecodeFile(configFile, builder); err != nil {
		t.Fatalf("Failed to decode TOML: %v", err)
	}

	builder.ApplySlicesToLists()

	// Empty arrays should result in empty lists
	if builder.RunArgs.Snapshot().Length() != 0 {
		t.Errorf("RunArgs length = %d, want 0", builder.RunArgs.Snapshot().Length())
	}
	if builder.BuildArgs.Snapshot().Length() != 0 {
		t.Errorf("BuildArgs length = %d, want 0", builder.BuildArgs.Snapshot().Length())
	}
}

func TestAppContextBuilder_BuildAfterTOML(t *testing.T) {
	builder := NewAppContextBuilder("0.11.0")

	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "build-test.toml")
	configContent := `
Variant = "notebook"
Daemon = true
WorkspacePort = "9000"
RunArgs = ["-e", "FOO=bar"]
`

	if err := os.WriteFile(configFile, []byte(configContent), 0644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	if _, err := toml.DecodeFile(configFile, builder); err != nil {
		t.Fatalf("Failed to decode TOML: %v", err)
	}

	builder.ApplySlicesToLists()

	// Build the immutable AppContext
	ctx := builder.Build()

	// Verify the values made it through to the AppContext
	if ctx.Variant() != "notebook" {
		t.Errorf("ctx.Variant() = %q, want %q", ctx.Variant(), "notebook")
	}
	if !ctx.Daemon() {
		t.Error("ctx.Daemon() = false, want true")
	}
	if ctx.WorkspacePort() != "9000" {
		t.Errorf("ctx.WorkspacePort() = %q, want %q", ctx.WorkspacePort(), "9000")
	}

	runArgs := ctx.RunArgs()
	if runArgs.Length() != 2 {
		t.Errorf("ctx.RunArgs().Length() = %d, want 2", runArgs.Length())
	}
	arg0, ok := runArgs.Get(0)
	if !ok {
		t.Error("ctx.RunArgs().Get(0) returned false")
	}
	if arg0 != "-e" {
		t.Errorf("ctx.RunArgs().Get(0) = %q, want %q", arg0, "-e")
	}
	arg1, ok := runArgs.Get(1)
	if !ok {
		t.Error("ctx.RunArgs().Get(1) returned false")
	}
	if arg1 != "FOO=bar" {
		t.Errorf("ctx.RunArgs().Get(1) = %q, want %q", arg1, "FOO=bar")
	}
}

func TestAppContextBuilder_TOMLInvalidFile(t *testing.T) {
	builder := NewAppContextBuilder("0.11.0")

	tmpDir := t.TempDir()
	configFile := filepath.Join(tmpDir, "invalid.toml")
	invalidContent := `
This is not valid TOML
Variant = 
`

	if err := os.WriteFile(configFile, []byte(invalidContent), 0644); err != nil {
		t.Fatalf("Failed to write test config: %v", err)
	}

	// Should return an error for invalid TOML
	if _, err := toml.DecodeFile(configFile, builder); err == nil {
		t.Error("Expected error for invalid TOML, got nil")
	}
}
