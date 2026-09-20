// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// ownershipMountPoint is where the project directory is mounted inside the
// throwaway helper container that stamps ownership.
const ownershipMountPoint = "/target"

// ownershipStampImage is the throwaway image used to run the chown. Matches the
// helper image already used for home-volume import/export.
const ownershipStampImage = "alpine"

// boothOwner is the uid:gid that .booth/ and the booth wrapper should read back
// as from inside a booth. It mirrors GetHostUID/GetHostGID on Windows, which
// report 1000 because a Windows host has no uid of its own.
const boothOwner = "1000:1000"

// boothOwnershipTargets returns the in-container paths to stamp, for the entries
// that actually exist beside targetPath. The booth wrapper is skipped when it is
// a directory, matching addReadOnlyBoothWrapper's own guard.
func boothOwnershipTargets(targetPath string) []string {
	var targets []string

	if info, err := os.Stat(filepath.Join(targetPath, ".booth")); err == nil && info.IsDir() {
		targets = append(targets, ownershipMountPoint+"/.booth")
	}
	if info, err := os.Stat(filepath.Join(targetPath, "booth")); err == nil && !info.IsDir() {
		targets = append(targets, ownershipMountPoint+"/booth")
	}

	return targets
}

// StampBoothOwnership makes .booth/ and the booth wrapper read back as coder
// rather than root from inside a booth, on Windows hosts. Best-effort: every
// failure is swallowed, because this is presentation only and must never take an
// init or reconfigure down with it.
//
// Both paths are bind-mounted READ-ONLY into the booth (see addReadOnlyBoothDir
// and addReadOnlyBoothWrapper), so nothing inside the container can chown them —
// a chown is a metadata write, and a read-only mount rejects it for root too.
// That read-only-ness is the only thing actually protecting .booth/ from the
// booth, since coder has passwordless sudo, so it must not be traded away.
//
// The way out is that ownership is not a property of the mount. Docker Desktop
// reaches a Windows drive through WSL drvfs mounted "uid=0;gid=0;metadata": the
// uid=0 is merely the default for files carrying no Unix metadata (hence the
// root:root), and "metadata" means a chown is stored as an NTFS extended
// attribute on the host file itself. So stamping it once here, through a
// writable mount in a throwaway container, is read back by every later
// read-only mount — ownership fixed, protection intact.
//
// Nothing to do on Linux or macOS: there the host uid is the real one and
// already matches, so the mount presents the right owner without help.
func StampBoothOwnership(targetPath string) {
	if runtime.GOOS != "windows" {
		return
	}

	// Never spawn a container from a test run. CI is Linux, so the guard above
	// already covers it there, but this package is also exercised on Windows dev
	// machines, where writeOutput is called by tests in several packages.
	if testing.Testing() {
		return
	}

	absPath, err := filepath.Abs(targetPath)
	if err != nil {
		return
	}

	targets := boothOwnershipTargets(absPath)
	if len(targets) == 0 {
		return
	}

	_ = docker.Docker(docker.DockerFlags{Silent: true}, "run", ilist.NewList(
		ilist.NewList("--rm"),
		ilist.NewList("-v", absPath+":"+ownershipMountPoint),
		ilist.NewList(ownershipStampImage),
		ilist.NewList("chown", "-R", boothOwner),
		ilist.NewList(targets...),
	))
}
