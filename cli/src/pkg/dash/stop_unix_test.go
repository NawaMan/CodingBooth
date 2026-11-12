// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

//go:build !windows

package dash

import (
	"os/exec"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestLogViewStopsTheFollowersChildren(t *testing.T) {
	// The log command starts a child that follows, as booth logs runs docker
	// logs; quitting the pager must end both.
	marker := "dash-logview-child-" + time.Now().Format("150405000000")
	logs := exec.Command("sh", "-c", "(exec -a "+marker+" sleep 60) & wait")
	logs.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	v := &logView{logs: logs, pager: exec.Command("sleep", "0.3")}
	var out strings.Builder
	v.SetStdout(&out)
	if err := v.Run(); err != nil {
		t.Fatal(err)
	}
	time.Sleep(200 * time.Millisecond)
	if ps, _ := exec.Command("pgrep", "-x", marker).Output(); strings.TrimSpace(string(ps)) != "" {
		_ = exec.Command("pkill", "-x", marker).Run()
		t.Errorf("the follower's child outlived the pager: pids %s", ps)
	}
}
