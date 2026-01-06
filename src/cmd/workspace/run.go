package main

import (
	"fmt"
	"os"

	"github.com/nawaman/workspace/src/pkg/workspace"
	wsinit "github.com/nawaman/workspace/src/pkg/workspace/init"
)

func runWorkspace(version string) {
	context := wsinit.InitializeAppContext(version, wsinit.DefaultInitializeAppContextBoundary{})
	context = workspace.ValidateVariant(context)
	context = workspace.EnsureDockerImage(context)

	fmt.Printf("%+v\n", context)

	// Execute workspace pipeline
	// ctx = workspace.PortDetermination(ctx)

	// TODO: Continue with remaining pipeline steps
	// - ShowDebugBanner
	// - SetupDind
	// - PrepareCommonArgs
	// - PrepareKeepAliveArgs
	// - PrepareTtyArgs
	// - RunAsDaemon / RunAsForeground / RunAsCommand

	os.Exit(0)
}
