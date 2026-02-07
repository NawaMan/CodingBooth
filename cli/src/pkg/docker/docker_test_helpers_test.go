// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker_test

import (
	"io"
	"os/exec"
	"testing"
)

func requireDocker(t *testing.T) {
	t.Helper()

	cmd := exec.Command("docker", "version")
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	if err := cmd.Run(); err != nil {
		t.Skipf("Skipping test - docker not available: %v", err)
	}
}

