package appctx

import (
	"os"
	"testing"

	"github.com/nawaman/workspace/cli/src/pkg/ilist"
	"github.com/nawaman/workspace/cli/src/pkg/nillable"
)

func TestAppConfig_Clone(t *testing.T) {
	// Create a populated config
	config := &AppConfig{
		Verbose:     nillable.NewNillableBool(true),
		ProjectName: "original",
		CommonArgs:  ilist.SemicolonStringList{},
	}
	// Manually populate ilist since it doesn't have a public constructor in this scope easily without decoding or using NewList
	// But SemicolonStringList wraps List[string], so we can rely on Decode or direct assignment if fields were public (they are not).
	// We'll use Decode to simulate population.
	config.CommonArgs.Decode("a;b")

	// Clone it
	cloned := config.Clone()

	// Verify deep copy
	if cloned.Verbose.ValueOr(false) != true {
		t.Error("Verbose mismatch")
	}
	if cloned.ProjectName != "original" {
		t.Error("ProjectName mismatch")
	}
	if cloned.CommonArgs.Length() != 2 {
		t.Errorf("CommonArgs length mismatch: %d", cloned.CommonArgs.Length())
	}

	// Modify original
	config.Verbose = nillable.NewNillableBool(false)
	config.ProjectName = "modified"
	// SemicolonStringList is immutable (List[string]), but let's verify reassignment of the field in struct doesn't affect clone
	config.CommonArgs.Decode("c")

	if cloned.Verbose.ValueOr(false) != true {
		t.Error("Clone affected by original modification (Verbose)")
	}
	if cloned.ProjectName != "original" {
		t.Error("Clone affected by original modification (ProjectName)")
	}
	if cloned.CommonArgs.At(0) != "a" {
		t.Error("Clone affected by original modification (CommonArgs)")
	}
}

func TestAppConfig_ReadFromEnvVars(t *testing.T) {
	os.Setenv("WS_COMMON_ARGS", "foo;bar")
	defer os.Unsetenv("WS_COMMON_ARGS")

	config := &AppConfig{}
	err := ReadFromEnvVars(config)
	if err != nil {
		t.Fatalf("ReadFromEnvVars failed: %v", err)
	}

	if config.CommonArgs.Length() != 2 {
		t.Errorf("Expected 2 common args, got %d", config.CommonArgs.Length())
	}
	if config.CommonArgs.At(0) != "foo" || config.CommonArgs.At(1) != "bar" {
		t.Errorf("Unexpected common args: %v", config.CommonArgs)
	}
}
