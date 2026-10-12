// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package hostskip skips a test whose subject does not exist on the host
// running it.
//
// Most of this CLI is the same code everywhere, and its tests should run
// everywhere — that is what the fakebin package is for. A few tests are not
// like that: they are *about* something only a Unix host has. A permission
// bit is the common case. Windows has no mode bits at all; os.Chmod there
// toggles one read-only flag and Stat reports a mode of 0666 or 0777 whatever
// was asked for, so `MkdirAll(dir, 0o700)` cannot be checked by reading the
// mode back. The product is not wrong on Windows — the booth's own files are
// made inside the container, and Docker Desktop maps what the host has — there
// is simply nothing on the host to assert.
//
// The skips are named after what is missing, so a run on Windows says why
// rather than going quietly green:
//
//	hostskip.NoUnixModes(t)   // permission bits read back as they were set
//	hostskip.NoUnixPaths(t)   // /etc, /dev, / and friends
//	hostskip.NoSymlinks(t)    // creating one needs a privilege here
//
// Reach for one only when the behaviour cannot exist on the host. A test that
// merely *expects* a Unix answer — a "/"-joined path, a POSIX shell script —
// belongs on every platform, with the expectation written so it holds on each.
package hostskip

import (
	"os"
	"path/filepath"
	"runtime"
)

// TB is the part of *testing.T this package needs, so a helper for tests does
// not drag the testing package into the build.
type TB interface {
	Helper()
	Skipf(format string, args ...any)
}

// UnixModes reports whether a file's permission bits on this host mean what
// they say.
func UnixModes() bool { return runtime.GOOS != "windows" }

// NoUnixModes skips a test that reads a permission bit back after setting it.
func NoUnixModes(t TB) {
	t.Helper()
	if !UnixModes() {
		t.Skipf("%s has no Unix permission bits: a mode set here cannot be read back", runtime.GOOS)
	}
}

// UnixPaths reports whether the absolute paths this project treats as the
// host's own — /etc, /dev, /var/lib/docker, / — are this host's.
func UnixPaths() bool { return runtime.GOOS != "windows" }

// NoUnixPaths skips a test whose subject is a Unix absolute path: a device
// under /dev, a system folder a mount must be judged against, or a container
// path mirrored from the host's own layout.
func NoUnixPaths(t TB) {
	t.Helper()
	if !UnixPaths() {
		t.Skipf("%s does not have the Unix paths this checks (/etc, /dev, /)", runtime.GOOS)
	}
}

// NoSymlinks skips a test that has to create a symbolic link when this host
// will not let it. Windows can, but only for an administrator or with
// Developer Mode on, so the only honest check is to try one.
func NoSymlinks(t TB) {
	t.Helper()
	dir, err := os.MkdirTemp("", "cb-symlink-probe")
	if err != nil {
		t.Skipf("cannot probe for symlink support: %v", err)
		return
	}
	defer os.RemoveAll(dir)
	target := filepath.Join(dir, "target")
	if err := os.WriteFile(target, nil, 0o644); err != nil {
		t.Skipf("cannot probe for symlink support: %v", err)
		return
	}
	if err := os.Symlink(target, filepath.Join(dir, "link")); err != nil {
		t.Skipf("this host will not create a symlink: %v", err)
	}
}
