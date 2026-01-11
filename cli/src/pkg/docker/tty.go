// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"os"

	"golang.org/x/term"
)

// IsTTY returns true if the given file descriptor is a terminal.
// This is useful for determining if -it flags should be used with docker run.
func IsTTY(fd uintptr) bool {
	return term.IsTerminal(int(fd))
}

// IsStdinTTY returns true if stdin is connected to a terminal.
// Use this to determine if interactive mode (-it) is available.
func IsStdinTTY() bool {
	return IsTTY(os.Stdin.Fd())
}

// IsStdoutTTY returns true if stdout is connected to a terminal.
func IsStdoutTTY() bool {
	return IsTTY(os.Stdout.Fd())
}

// HasInteractiveTTY returns true if both stdin and stdout are connected to a terminal.
// This is the recommended check before using -it flags with docker run.
func HasInteractiveTTY() bool {
	return IsStdinTTY() && IsStdoutTTY()
}
