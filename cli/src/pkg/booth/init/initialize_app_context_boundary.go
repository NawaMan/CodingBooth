// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"github.com/nawaman/coding-booth/src/pkg/appctx"
	"github.com/nawaman/coding-booth/src/pkg/ilist"
)

type InitializeAppContextBoundary interface {
	// Args returns the command-line arguments
	ArgList() ilist.List[string]

	PopulateAppConfigFromEnvVars(config *appctx.AppConfig) error

	// detectTimezone detects the system timezone
	DetectTimezone() string

	// getCurrentPath returns the current working directory, handling MSYS/Git Bash on Windows
	GetCurrentPath() string

	// getHostUID returns the current user's UID as a string
	GetHostUID() string

	// getHostGID returns the current user's GID as a string
	GetHostGID() string
}
