package init

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"github.com/kelseyhightower/envconfig"
	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/ilist"
)

type DefaultInitializeAppContextBoundary struct{}

func (DefaultInitializeAppContextBoundary) ArgList() ilist.List[string] {
	return ilist.NewListFromSlice(os.Args)
}

func (DefaultInitializeAppContextBoundary) PopulateAppConfigFromEnvVars(config *appctx.AppConfig) error {
	return envconfig.Process("", config)
}

func (DefaultInitializeAppContextBoundary) DetectTimezone() string {
	// Try to get timezone from environment
	if tz := os.Getenv("TZ"); tz != "" {
		return tz
	}

	// Use Go's time package to detect local timezone
	now := time.Now()
	zone, _ := now.Zone()

	// If we can get the IANA timezone name, use it
	if loc := now.Location(); loc != nil && loc.String() != "Local" {
		return loc.String()
	}

	// Fallback to zone abbreviation (e.g., "EST", "PST")
	if zone != "" {
		return zone
	}

	// Ultimate fallback
	return "UTC"
}

func (DefaultInitializeAppContextBoundary) GetCurrentPath() string {
	cwd, err := os.Getwd()
	if err != nil {
		panic(fmt.Errorf("Error getting current directory: %v", err))
	}

	if runtime.GOOS == "windows" {
		return cwd
	}

	return cwd
}

func (DefaultInitializeAppContextBoundary) GetHostGID() string {
	if runtime.GOOS == "windows" {
		// Windows doesn't have GIDs, return a default
		return "1000"
	}

	// Use id -g command
	cmd := exec.Command("id", "-g")
	output, err := cmd.Output()
	if err != nil {
		return "1000" // fallback
	}

	return strings.TrimSpace(string(output))
}

func (DefaultInitializeAppContextBoundary) GetHostUID() string {
	if runtime.GOOS == "windows" {
		// Windows doesn't have UIDs, return a default
		return "1000"
	}

	// Use id -u command
	cmd := exec.Command("id", "-u")
	output, err := cmd.Output()
	if err != nil {
		return "1000" // fallback
	}

	return strings.TrimSpace(string(output))
}
