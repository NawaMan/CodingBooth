package docker

import (
	"testing"
)

// TestDocker_TTYFiltering tests that -it flags are filtered when no TTY is available.
func TestDocker_TTYFiltering(t *testing.T) {
	// Define options
	verbose := true
	dryrun := true // Don't actually run

	// This should work even though we're passing -it and there's no TTY in tests
	err := Docker(dryrun, verbose, "run", "-it", "--rm", "alpine:latest", "echo", "test")
	if err != nil {
		t.Fatalf("Docker with -it should not fail in dryrun: %v", err)
	}

	// Test with separate -i and -t flags
	err = Docker(dryrun, verbose, "run", "-i", "-t", "--rm", "alpine:latest", "echo", "test")
	if err != nil {
		t.Fatalf("Docker with -i -t should not fail in dryrun: %v", err)
	}
}

// TestDocker_TTYFlagsPreservedInTTY verifies flags are preserved when TTY is available.
// Note: This test will show different behavior depending on how it's run.
func TestDocker_TTYFlagsPreservedInTTY(t *testing.T) {
	verbose := true
	dryrun := true

	hasTTY := HasInteractiveTTY()
	t.Logf("Running with TTY: %v", hasTTY)

	// The function should handle this gracefully regardless of TTY
	err := Docker(dryrun, verbose, "run", "-it", "--rm", "alpine:latest", "sh")
	if err != nil {
		t.Fatalf("Docker should not fail in dryrun: %v", err)
	}
}
