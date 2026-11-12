// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

//go:build windows

package main

import "os/exec"

// detach: Windows has no /dev/tty for a background command to ask on.
func detach(cmd *exec.Cmd) *exec.Cmd { return cmd }
