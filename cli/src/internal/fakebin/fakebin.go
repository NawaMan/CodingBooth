// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package fakebin puts stand-in executables on a test's PATH.
//
// A test that wants to know what the CLI would run at a container engine needs
// a `docker`, `podman` or `container` it controls. The obvious way to write one
// is a shell script — and that is what every helper here replaced:
//
//	os.WriteFile(filepath.Join(dir, "docker"), []byte("#!/bin/sh\n..."), 0o755)
//
// which cannot work on Windows. `exec.LookPath("docker")` there only considers
// the extensions in PATHEXT, so an extensionless file is not an executable no
// matter what its first line says — the engine is simply never found. Every
// such test then exercised the "no engine installed" path instead of the one it
// named, and the ones whose expectation happened to be the fallback passed
// while proving nothing.
//
// A stub here is a hard link to the running test binary instead, which is a
// real executable on every platform. The copy re-enters its own TestMain, where
// Serve recognizes it by the name it was invoked under and hands it to the
// package's own handler rather than running the tests again:
//
//	func TestMain(m *testing.M) {
//	    fakebin.Serve(fakeEngineMain)   // returns at once in the test process
//	    os.Exit(m.Run())
//	}
//
//	func TestSomething(t *testing.T) {
//	    dir := fakebin.OnPath(t, "docker", "podman")
//	    ...
//	}
//
// What each stub *does* stays with the package that installs it: the handler
// reads whatever the test put in the environment (a JSON spec, a fixture path)
// and writes to stdout. Nothing is interpreted by a shell on the way, so the
// arguments the handler sees are exactly the ones the CLI passed — which a
// `cmd.exe` shim forwarding to `sh` could not promise (it eats the braces in
// `--format {{.Names}}`).
package fakebin

import (
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// envNames carries the installed stub names to the re-entered process. It is
// also the flag that says a process *is* a stub: a test binary started by `go
// test` never has it set, because OnPath sets it through the test's own
// environment, long after TestMain has run.
const envNames = "CB_FAKEBIN_NAMES"

// TB is the part of *testing.T this package needs, so a helper for tests does
// not drag the testing package into the build.
type TB interface {
	Helper()
	Fatalf(format string, args ...any)
	TempDir() string
	Setenv(key, value string)
}

// Serve hands a re-entered stub process to handler and exits with what the
// handler returns. In a test process it returns immediately, so TestMain can
// call it unconditionally as its first statement.
//
// handler is given the name the stub was invoked under ("docker", not
// "docker.exe") and the arguments after it.
func Serve(handler func(name string, args []string) int) {
	names := os.Getenv(envNames)
	if names == "" {
		return
	}
	name := strings.TrimSuffix(filepath.Base(os.Args[0]), ".exe")
	for _, installed := range strings.Split(names, ",") {
		if installed == name {
			os.Exit(handler(name, os.Args[1:]))
		}
	}
}

// OnPath installs a stub for each name in a directory of its own, makes that
// directory the whole PATH, and returns it. The directory is the natural place
// for a call log or a fixture the handler reads back.
func OnPath(t TB, names ...string) string {
	t.Helper()
	dir := Install(t, names...)
	t.Setenv("PATH", dir)
	return dir
}

// Install writes the stubs into a new directory and returns it, leaving PATH
// alone — for a test that needs the directory somewhere other than on PATH, or
// that assembles a PATH of its own.
func Install(t TB, names ...string) string {
	t.Helper()
	dir := t.TempDir()
	InstallInto(t, dir, names...)
	return dir
}

// InstallInto writes the stubs into a directory the caller already has, for a
// test that keeps a call log or a fixture beside them.
func InstallInto(t TB, dir string, names ...string) {
	t.Helper()
	self, err := os.Executable()
	if err != nil {
		t.Fatalf("fakebin: cannot find the test binary: %v", err)
	}
	for _, name := range names {
		target := filepath.Join(dir, name)
		if runtime.GOOS == "windows" {
			target += ".exe"
		}
		if err := link(self, target); err != nil {
			t.Fatalf("fakebin: cannot install %s: %v", name, err)
		}
	}
	t.Setenv(envNames, strings.Join(names, ","))
}

// link points target at the test binary. A hard link costs nothing and needs no
// privilege; a copy is the fallback for the case it cannot cover — a temp
// directory on another volume, which Windows hands out often enough.
func link(self, target string) error {
	if err := os.Link(self, target); err == nil {
		return nil
	}
	source, err := os.Open(self)
	if err != nil {
		return err
	}
	defer source.Close()
	copied, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o755)
	if err != nil {
		return err
	}
	if _, err := io.Copy(copied, source); err != nil {
		copied.Close()
		return err
	}
	return copied.Close()
}
