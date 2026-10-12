// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/internal/fakebin"
)

// Three kinds of test here need a container engine they control: the lookups in
// engines_test.go, `booth copy` in copy_test.go, and readLivePorts in
// expose_test.go. Each used to write its own `#!/bin/sh` script, which Windows
// cannot run at all (see the fakebin package), so all three now install the
// same stub — a copy of this test binary — and say through the environment
// which of them installed it.
const envFakeMode = "CB_TEST_FAKE_MODE"

const (
	fakeModeEngines = "engines" // installFakeEngines, engines_test.go
	fakeModeCopy    = "copy"    // installCopyEngine, copy_test.go
	fakeModePort    = "port"    // fakeEngines, expose_test.go
)

// TestMain hands a stub process to the handler for the mode that installed it,
// instead of running this package's tests again.
func TestMain(m *testing.M) {
	fakebin.Serve(func(name string, args []string) int {
		switch os.Getenv(envFakeMode) {
		case fakeModeEngines:
			return fakeEnginesMain(name, args)
		case fakeModeCopy:
			return fakeCopyMain(name, args)
		case fakeModePort:
			return fakePortMain(name, args)
		}
		fmt.Fprintf(os.Stderr, "%s: no fake engine mode set\n", name)
		return 127
	})
	os.Exit(m.Run())
}

// appendCall logs one call to the file named by env, as the stub it replaced
// did. A test that does not ask for a log leaves env unset.
func appendCall(env, line string) {
	path := os.Getenv(env)
	if path == "" {
		return
	}
	file, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer file.Close()
	file.WriteString(line)
}

// lastArg is the name an `inspect` call ends with — the shell's `for last; do
// :; done`.
func lastArg(args []string) string {
	if len(args) == 0 {
		return ""
	}
	return args[len(args)-1]
}

func joinCall(name string, args []string) string {
	return strings.TrimRight(name+" "+strings.Join(args, " "), " ") + "\n"
}
