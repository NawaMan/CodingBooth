package main

import (
	"fmt"
	"os"

	wsinit "github.com/nawaman/workspace/src/pkg/workspace/init"
)

func runWorkspace() {
	context := wsinit.InitializeAppContext(wsinit.DefaultInitializeAppContextBoundary{})

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
