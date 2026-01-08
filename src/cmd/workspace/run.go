package main

import (
	"fmt"
	"os"

	"github.com/nawaman/workspace/src/pkg/workspace"
	wsinit "github.com/nawaman/workspace/src/pkg/workspace/init"
)

func runWorkspace(version string) {
	context := wsinit.InitializeAppContext(version, wsinit.DefaultInitializeAppContextBoundary{})

	if context.Verbose() {
		fmt.Printf("%+v\n", context)
	}

	runner := workspace.NewWorkspaceRunner(context)
	err := runner.Run()
	if err != nil {
		fmt.Println("❌ Workspace failed with error:", err)
		os.Exit(1)
		return
	}
	os.Exit(0)
}
