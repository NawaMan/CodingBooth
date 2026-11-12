// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"os/exec"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestLogKeyOpensViewerForBoothRows(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f, boothAt("fixer", "/home/u/dev/proj/worktree/fix"), stopped("old"))

	// A worktree with no booth has no log.
	m2, cmd := press(t, m, "l")
	if cmd != nil || len(f.logViewed) != 0 || !strings.Contains(m2.status, "No booth on main") {
		t.Fatalf("l on a bare worktree: cmd %v viewed %v status %q", cmd != nil, f.logViewed, m2.status)
	}
	m, _ = press(t, m, "down")
	if _, cmd = press(t, m, "l"); cmd == nil {
		t.Fatal("l on a booth must open its log")
	}
	m, _ = press(t, m, "end")
	press(t, m, "l") // a stopped booth's log too
	if want := []string{"fixer", "old"}; !reflect.DeepEqual(f.logViewed, want) {
		t.Errorf("viewed %v, want %v", f.logViewed, want)
	}
}

func TestLogViewPipesIntoPager(t *testing.T) {
	var out strings.Builder
	v := &logView{
		logs:  exec.Command("printf", "line one\\nline two\\n"),
		pager: exec.Command("cat"),
	}
	v.SetStdin(strings.NewReader(""))
	v.SetStdout(&out)
	v.SetStderr(&out)
	if err := v.Run(); err != nil {
		t.Fatal(err)
	}
	if out.String() != "line one\nline two\n" {
		t.Errorf("pager showed %q", out.String())
	}
}

func TestLogViewStopsFollowingWhenPagerQuits(t *testing.T) {
	// A log that never ends (following), and a pager that quits at once.
	v := &logView{logs: exec.Command("sleep", "60"), pager: exec.Command("true")}
	var out strings.Builder
	v.SetStdout(&out)
	done := make(chan error, 1)
	go func() { done <- v.Run() }()
	select {
	case err := <-done:
		if err != nil {
			t.Errorf("Run = %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the log command outlived the pager")
	}
}

func TestLogViewWithoutPager(t *testing.T) {
	var out strings.Builder
	v := &logView{logs: exec.Command("sh", "-c", "echo hi; exit 130")} // as after ctrl+c
	v.SetStdout(&out)
	if err := v.Run(); err != nil || out.String() != "hi\n" {
		t.Errorf("Run = %v, out %q; ctrl+c's exit is how it ends", err, out.String())
	}
	missing := &logView{logs: exec.Command("/no/such/booth")}
	if err := missing.Run(); err == nil {
		t.Error("a log command that cannot run is a failure")
	}
}
