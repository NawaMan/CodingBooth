// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

//go:build !windows

package main

import (
	"os/exec"
	"syscall"
)

// detach runs cmd in a session of its own, with no controlling terminal: a
// command booth dashboard runs in the background can then never read the keys
// typed into the dashboard (booth asks some questions on /dev/tty, past
// stdin). Asked with no terminal, booth refuses and says which flag allows it.
func detach(cmd *exec.Cmd) *exec.Cmd {
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	return cmd
}
