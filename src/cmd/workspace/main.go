package main

import (
	"fmt"
	"os"

	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/ilist"
)

const version = "0.11.0"

func main() {
	fmt.Printf("WorkSpace v%s - Go Edition\n", version)
	fmt.Printf("AppContext Demo: Immutable/Mutable Pattern\n\n")

	// Create mutable builder for construction
	builder := appctx.NewAppContextBuilder(version)

	// Configure workspace settings via builder
	builder.WorkspacePath = "/home/user/workspace"
	builder.ContainerName = "my-workspace"
	builder.HostUID = "1000"
	builder.HostGID = "1000"
	builder.HostPort = "10000"
	builder.Verbose = true

	// Build Docker args incrementally
	builder.AppendCommonArg("--name", builder.ContainerName)
	builder.AppendCommonArg("-e", "HOST_UID="+builder.HostUID)
	builder.AppendCommonArg("-e", "HOST_GID="+builder.HostGID)
	builder.AppendCommonArg("-v", builder.WorkspacePath+":/home/coder/workspace")
	builder.AppendCommonArg("-w", "/home/coder/workspace")
	builder.AppendCommonArg("-p", builder.HostPort+":10000")

	// Build keepalive args based on flag
	if !builder.Keepalive {
		builder.KeepaliveArgs = ilist.NewAppendableListFrom("--rm")
	}

	// Build immutable context
	ctx := builder.Build()

	// Display immutable context
	fmt.Printf("=== Immutable AppContext ===\n")
	fmt.Printf("Configuration:\n")
	fmt.Printf("  Workspace Path: %s\n", ctx.WorkspacePath())
	fmt.Printf("  Container Name: %s\n", ctx.ContainerName())
	fmt.Printf("  Host Port:      %s\n", ctx.HostPort())
	fmt.Printf("  Verbose:        %v\n", ctx.Verbose())
	fmt.Printf("\n")

	fmt.Printf("Common Args (%d):\n", ctx.CommonArgs().Length())
	ctx.CommonArgs().Range(func(index int, value string) bool {
		fmt.Printf("  [%d] %s\n", index, value)
		return true
	})
	fmt.Printf("\n")

	fmt.Printf("KeepAlive Args (%d):\n", ctx.KeepAliveArgs().Length())
	ctx.KeepAliveArgs().Range(func(index int, value string) bool {
		fmt.Printf("  [%d] %s\n", index, value)
		return true
	})
	fmt.Printf("\n")

	// Demonstrate immutability: modify builder after Build()
	fmt.Printf("=== Demonstrating Immutability ===\n")
	builder.AppendCommonArg("--extra", "arg")
	fmt.Printf("After adding --extra arg to builder:\n")
	fmt.Printf("  Original context still has %d args (immutable)\n", ctx.CommonArgs().Length())
	fmt.Printf("\n")

	// Demonstrate ToBuilder: convert immutable → mutable
	fmt.Printf("=== Demonstrating ToBuilder() ===\n")
	builder2 := ctx.ToBuilder()
	builder2.AppendCommonArg("--new", "value")
	builder2.WorkspacePath = "/new/workspace"

	ctx2 := builder2.Build()
	fmt.Printf("Original context workspace: %s (unchanged)\n", ctx.WorkspacePath())
	fmt.Printf("New context workspace:      %s (modified)\n", ctx2.WorkspacePath())
	fmt.Printf("Original context args:      %d (unchanged)\n", ctx.CommonArgs().Length())
	fmt.Printf("New context args:           %d (modified)\n", ctx2.CommonArgs().Length())
	fmt.Printf("\n")

	// Demonstrate round-trip
	fmt.Printf("=== Pattern Summary ===\n")
	fmt.Printf("1. Create builder:  NewAppContextBuilder()\n")
	fmt.Printf("2. Configure:       builder.FieldName = value / builder.AppendXxx()\n")
	fmt.Printf("3. Build snapshot:  ctx := builder.Build()\n")
	fmt.Printf("4. Use immutable:   ctx.GetXxx() / ctx.CommonArgs()\n")
	fmt.Printf("5. Convert back:    builder := ctx.ToBuilder()\n")
	fmt.Printf("\n")
	fmt.Printf("✅ Immutable by default, mutable when needed\n")
	fmt.Printf("✅ Matches List/AppendableList pattern\n")

	os.Exit(0)
}
