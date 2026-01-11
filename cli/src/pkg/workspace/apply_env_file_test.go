package workspace

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/ilist"
	"github.com/nawaman/workspace/src/pkg/nillable"
)

func TestApplyEnvFile_Default(t *testing.T) {
	// Setup temporary directory as workspace
	tmpDir, err := os.MkdirTemp("", "ws_test_default")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	// Create .env file in workspace
	envFile := filepath.Join(tmpDir, ".env")
	if err := os.WriteFile(envFile, []byte("FOO=BAR"), 0644); err != nil {
		t.Fatal(err)
	}

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	// Mock Workspace path by assuming the function uses builder.Config or we can set it somehow?
	// ApplyEnvFile uses ctx.Workspace() which usually comes from Config.Workspace or calculated.
	// Let's check how ctx.Workspace() is derived. It seems it might be missing in AppContextBuilder for simple tests if not set.
	// Looking at AppContext (implied from previous reads), it seems to have a Workspace() method.
	// For testing, we might need to set the Workspace dir in the context.
	// Let's assume there is a way to set it in builder or we'll need to mock it.

	// Wait, ApplyEnvFile logic:
	// candidate := ctx.Workspace() + "/.env"
	// if candidate == "" { candidate = "./.env" }

	// If ctx.Workspace() is empty, it checks "./.env".
	// So we can change Cwd to tmpDir to test "./.env" path or set Workspace in context.

	// Set Workspace explicitely to tmpDir
	builder.Config.Workspace = nillable.NewNillableString(tmpDir)

	ctx := builder.Build()

	// Execute
	newCtx := ApplyEnvFile(ctx)

	// Verify
	// It should have added --env-file ./.env to CommonArgs
	args := flattenArgs(newCtx.CommonArgs())
	found := false
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			if args[i+1] == "./.env" || args[i+1] == envFile {
				found = true
				break
			}
		}
	}

	if !found {
		t.Errorf("Expected --env-file arg to be added, got args: %v", args)
	}
}

func TestApplyEnvFile_Explicit(t *testing.T) {
	tmpDir, err := os.MkdirTemp("", "ws_test_explicit")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	myEnv := filepath.Join(tmpDir, "my.env")
	if err := os.WriteFile(myEnv, []byte("Make=ItSo"), 0644); err != nil {
		t.Fatal(err)
	}

	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.EnvFile = myEnv // Explicitly set

	ctx := builder.Build()
	newCtx := ApplyEnvFile(ctx)

	args := flattenArgs(newCtx.CommonArgs())
	found := false
	for i, arg := range args {
		if arg == "--env-file" && i+1 < len(args) {
			if args[i+1] == myEnv {
				found = true
				break
			}
		}
	}
	if !found {
		t.Errorf("Expected --env-file %s, got args: %v", myEnv, args)
	}
}

func TestApplyEnvFile_Disabled(t *testing.T) {
	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.EnvFile = "-" // Explicitly disabled
	builder.Config.Verbose = nillable.NewNillableBool(true)

	ctx := builder.Build()
	newCtx := ApplyEnvFile(ctx)

	args := flattenArgs(newCtx.CommonArgs())
	for _, arg := range args {
		if arg == "--env-file" {
			t.Errorf("Expected NO --env-file arg when disabled, got args: %v", args)
		}
	}
}
