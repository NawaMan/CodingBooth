// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"testing"
)

// TestHasInteractiveTTY tests the TTY detection functions.
// Note: This test will behave differently depending on how it's run:
// - Running in a terminal: will detect TTY
// - Running through go test: will NOT detect TTY
func TestHasInteractiveTTY(t *testing.T) {
	// Just verify the functions don't panic
	_ = IsStdinTTY()
	_ = IsStdoutTTY()
	hasTTY := HasInteractiveTTY()

	// When run through go test, there's typically no TTY
	t.Logf("HasInteractiveTTY: %v", hasTTY)
	t.Logf("IsStdinTTY: %v", IsStdinTTY())
	t.Logf("IsStdoutTTY: %v", IsStdoutTTY())
}

// Example usage of TTY detection for conditional -it flags
func ExampleHasInteractiveTTY() {
	// This shows how to conditionally add -it flags based on TTY availability
	args := []string{"run", "--rm", "alpine:latest", "sh"}

	// Only add -it if we have an interactive TTY
	if HasInteractiveTTY() {
		// Insert -it after "run"
		args = append([]string{"run", "-it"}, args[1:]...)
	}

	// Now args will have -it only if running in a terminal
	_ = args
}
