// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"fmt"
	"os"
	"os/user"
	"runtime"
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
	envconfig.Process("", config)
	return nil
}

func (DefaultInitializeAppContextBoundary) DetectTimezone() string {
	// Try to get timezone from environment
	if tz := os.Getenv("TIMEZONE"); tz != "" {
		return tz
	}

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

func (DefaultInitializeAppContextBoundary) GetHostUID() string {
	if runtime.GOOS == "windows" {
		return "1000"
	}

	u, err := user.Current()
	if err != nil {
		return "1000"
	}
	return u.Uid
}

func (DefaultInitializeAppContextBoundary) GetHostGID() string {
	if runtime.GOOS == "windows" {
		return "1000"
	}

	u, err := user.Current()
	if err != nil {
		return "1000"
	}
	return u.Gid
}
