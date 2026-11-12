// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

//go:build !windows

package dash

import (
	"os/exec"
	"syscall"
)

// stopGroup ends a command started in a session of its own, children and
// all: `booth logs -f` runs `docker logs --follow`, which would otherwise
// outlive it, waiting on a log that may never write again.
func stopGroup(cmd *exec.Cmd) {
	if cmd.Process == nil {
		return
	}
	if cmd.SysProcAttr != nil && (cmd.SysProcAttr.Setsid || cmd.SysProcAttr.Setpgid) {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		return
	}
	_ = cmd.Process.Kill()
}
