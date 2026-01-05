package init

import (
	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/ilist"
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
