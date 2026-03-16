// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/kelseyhightower/envconfig"
	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
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

	// If we can get the IANA timezone name from Go, use it
	if loc := now.Location(); loc != nil && loc.String() != "Local" {
		return loc.String()
	}

	// Read /etc/timezone (Debian/Ubuntu)
	if data, err := os.ReadFile("/etc/timezone"); err == nil {
		if tz := strings.TrimSpace(string(data)); tz != "" {
			return tz
		}
	}

	// Resolve /etc/localtime symlink to extract IANA name (e.g., /usr/share/zoneinfo/America/Toronto)
	if target, err := filepath.EvalSymlinks("/etc/localtime"); err == nil {
		const marker = "/zoneinfo/"
		if idx := strings.Index(target, marker); idx != -1 {
			return target[idx+len(marker):]
		}
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
