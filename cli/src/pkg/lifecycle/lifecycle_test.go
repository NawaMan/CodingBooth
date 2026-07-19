// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"strings"
	"testing"
)

func TestReadConfirmation(t *testing.T) {
	tests := []struct {
		input    string
		expected bool
	}{
		{input: "y\n", expected: true},
		{input: "YES\n", expected: true},
		{input: "n\n", expected: false},
		{input: "\n", expected: false},
	}

	for _, test := range tests {
		got, err := readConfirmation(strings.NewReader(test.input))
		if err != nil {
			t.Fatalf("readConfirmation(%q) returned error: %v", test.input, err)
		}
		if got != test.expected {
			t.Fatalf("readConfirmation(%q) = %t, want %t", test.input, got, test.expected)
		}
	}
}

func TestExitCode(t *testing.T) {
	if code := ExitCode(nil); code != 0 {
		t.Fatalf("ExitCode(nil) = %d, want 0", code)
	}

	err := commandExit(2, "bad input")
	if code := ExitCode(err); code != 2 {
		t.Fatalf("ExitCode(commandExit(2,...)) = %d, want 2", code)
	}
}

func TestPruneArgValidation(t *testing.T) {
	err := Prune([]string{"--unknown"}, strings.NewReader(""), &strings.Builder{}, &strings.Builder{})
	if err == nil {
		t.Fatal("expected argument parsing error")
	}
	if code := ExitCode(err); code != 2 {
		t.Fatalf("ExitCode(err) = %d, want 2", code)
	}
}

func TestSanitizeProjectName(t *testing.T) {
	cases := map[string]string{
		"my-project":     "my-project",
		"my project":     "my-project",
		"my@project#123": "my-project-123",
		"":               "booth",
	}

	for in, want := range cases {
		got := sanitizeProjectName(in)
		if got != want {
			t.Fatalf("sanitizeProjectName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestResolveSingleContainerByCodePathAmbiguous(t *testing.T) {
	containers := []managedContainer{
		{Name: "a", CodePath: normalizeCodePath("."), State: "exited"},
		{Name: "b", CodePath: normalizeCodePath("."), State: "exited"},
	}

	_, err := resolveSingleContainer(containers, "", ".", nil, stateStopped)
	if err == nil {
		t.Fatal("expected ambiguous code-path error")
	}
	if !strings.Contains(err.Error(), "multiple booths match code path") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestResolveSingleContainerStateValidation(t *testing.T) {
	containers := []managedContainer{{Name: "demo", State: "running"}}

	_, err := resolveSingleContainer(containers, "demo", "", nil, stateStopped)
	if err == nil {
		t.Fatal("expected already running error")
	}
	if !strings.Contains(err.Error(), "already running") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestConnectPlanRunningWithoutRun(t *testing.T) {
	containers := []managedContainer{{Name: "demo", State: "running"}}

	target, action, err := connectPlan(containers, "demo", nil, false)
	if err != nil {
		t.Fatalf("connectPlan returned error: %v", err)
	}
	if target.Name != "demo" {
		t.Fatalf("target.Name = %q, want %q", target.Name, "demo")
	}
	if action != connectUse {
		t.Fatalf("action = %d, want connectUse for an already-running booth", action)
	}
}

func TestConnectPlanStoppedWithoutRun(t *testing.T) {
	containers := []managedContainer{{Name: "demo", State: "exited"}}

	_, _, err := connectPlan(containers, "demo", nil, false)
	if err == nil {
		t.Fatal("expected not-running error for a stopped booth without --run")
	}
	if !strings.Contains(err.Error(), "is not running") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestConnectPlanMissingWithoutRun(t *testing.T) {
	containers := []managedContainer{{Name: "demo", State: "running"}}

	_, _, err := connectPlan(containers, "ghost", nil, false)
	if err == nil {
		t.Fatal("expected not-found error for a missing booth without --run")
	}
	if !strings.Contains(err.Error(), "not found") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestConnectPlanStoppedWithRun(t *testing.T) {
	containers := []managedContainer{{Name: "demo", State: "exited"}}

	target, action, err := connectPlan(containers, "demo", nil, true)
	if err != nil {
		t.Fatalf("connectPlan returned error: %v", err)
	}
	if target.Name != "demo" {
		t.Fatalf("target.Name = %q, want %q", target.Name, "demo")
	}
	if action != connectStart {
		t.Fatalf("action = %d, want connectStart for a stopped booth with --run", action)
	}
}

func TestConnectPlanRunningWithRun(t *testing.T) {
	containers := []managedContainer{{Name: "demo", State: "running"}}

	_, action, err := connectPlan(containers, "demo", nil, true)
	if err != nil {
		t.Fatalf("connectPlan returned error: %v", err)
	}
	if action != connectUse {
		t.Fatalf("action = %d, want connectUse for an already-running booth with --run", action)
	}
}

func TestConnectPlanMissingWithRun(t *testing.T) {
	containers := []managedContainer{{Name: "demo", State: "running"}}

	target, action, err := connectPlan(containers, "ghost", nil, true)
	if err != nil {
		t.Fatalf("connectPlan returned error: %v", err)
	}
	if action != connectRun {
		t.Fatalf("action = %d, want connectRun for a missing booth with --run", action)
	}
	if target.Name != "ghost" {
		t.Fatalf("target.Name = %q, want %q (name to run under)", target.Name, "ghost")
	}
}

func TestExtractPositionalAndFlagsRun(t *testing.T) {
	// --run is a boolean flag: it must not swallow the following positional.
	cases := [][]string{
		{"myproject", "--run"},
		{"--run", "myproject"},
	}

	for _, args := range cases {
		positional, flags := extractPositionalAndFlags(args)
		if len(positional) != 1 || positional[0] != "myproject" {
			t.Fatalf("extractPositionalAndFlags(%v) positional = %v, want [myproject]", args, positional)
		}
		if len(flags) != 1 || flags[0] != "--run" {
			t.Fatalf("extractPositionalAndFlags(%v) flags = %v, want [--run]", args, flags)
		}
	}
}

func TestExtractPositionalAndFlagsPort(t *testing.T) {
	// --port takes a value and must not swallow a later positional.
	cases := []struct {
		args       []string
		positional []string
		flags      []string
	}{
		{[]string{"myproject", "--port", "9000"}, []string{"myproject"}, []string{"--port", "9000"}},
		{[]string{"--port", "9000", "myproject"}, []string{"myproject"}, []string{"--port", "9000"}},
		{[]string{"--port", "NEXT", "--run", "myproject"}, []string{"myproject"}, []string{"--port", "NEXT", "--run"}},
		{[]string{"--accept-existing", "myproject"}, []string{"myproject"}, []string{"--accept-existing"}},
	}

	for _, tc := range cases {
		positional, flags := extractPositionalAndFlags(tc.args)
		if len(positional) != len(tc.positional) || (len(positional) > 0 && positional[0] != tc.positional[0]) {
			t.Fatalf("extractPositionalAndFlags(%v) positional = %v, want %v", tc.args, positional, tc.positional)
		}
		if strings.Join(flags, " ") != strings.Join(tc.flags, " ") {
			t.Fatalf("extractPositionalAndFlags(%v) flags = %v, want %v", tc.args, flags, tc.flags)
		}
	}
}

func TestIsComparablePort(t *testing.T) {
	if !isComparablePort("9000") {
		t.Fatal("numeric port should be comparable")
	}
	if isComparablePort("NEXT") || isComparablePort("next") || isComparablePort("RANDOM") {
		t.Fatal("NEXT/RANDOM should not be comparable")
	}
	if isComparablePort("NEXT:20000") || isComparablePort("random:30000") {
		t.Fatal("NEXT:base/RANDOM:base should not be comparable")
	}
	if isComparablePort("") {
		t.Fatal("empty port should not be comparable")
	}
}

func TestCreateIntentMismatches(t *testing.T) {
	target := managedContainer{Name: "demo", Port: "8080"}

	// No create flags → no mismatch
	if got := createIntentMismatches(target, connectCreateOpts{}); len(got) != 0 {
		t.Fatalf("no flags: mismatches = %v, want none", got)
	}

	// Matching port → no mismatch
	if got := createIntentMismatches(target, connectCreateOpts{port: "8080"}); len(got) != 0 {
		t.Fatalf("matching port: mismatches = %v, want none", got)
	}

	// NEXT/RANDOM → not asserted
	if got := createIntentMismatches(target, connectCreateOpts{port: "NEXT"}); len(got) != 0 {
		t.Fatalf("NEXT: mismatches = %v, want none", got)
	}
	if got := createIntentMismatches(target, connectCreateOpts{port: "RANDOM"}); len(got) != 0 {
		t.Fatalf("RANDOM: mismatches = %v, want none", got)
	}

	// Wrong port → mismatch
	got := createIntentMismatches(target, connectCreateOpts{port: "9000"})
	if len(got) != 1 || !strings.Contains(got[0], "9000") || !strings.Contains(got[0], "8080") {
		t.Fatalf("wrong port: mismatches = %v", got)
	}

	// No published port on booth but explicit numeric request → mismatch
	noPort := managedContainer{Name: "term"}
	got = createIntentMismatches(noPort, connectCreateOpts{port: "9000"})
	if len(got) != 1 || !strings.Contains(got[0], "no published host port") {
		t.Fatalf("empty port: mismatches = %v", got)
	}
}

func TestCheckCreateIntentAgainstExisting(t *testing.T) {
	target := managedContainer{Name: "demo", Port: "8080"}
	var stderr strings.Builder

	// Fail by default on mismatch
	err := checkCreateIntentAgainstExisting(target, connectCreateOpts{port: "9000"}, &stderr)
	if err == nil {
		t.Fatal("expected mismatch error")
	}
	if code := ExitCode(err); code != 1 {
		t.Fatalf("ExitCode = %d, want 1", code)
	}
	if !strings.Contains(err.Error(), "--accept-existing") {
		t.Fatalf("error should mention --accept-existing: %v", err)
	}

	// --accept-existing: warn and continue
	stderr.Reset()
	err = checkCreateIntentAgainstExisting(target, connectCreateOpts{port: "9000", acceptExisting: true}, &stderr)
	if err != nil {
		t.Fatalf("accept-existing should not error: %v", err)
	}
	if !strings.Contains(stderr.String(), "Warning:") || !strings.Contains(stderr.String(), "accept-existing") {
		t.Fatalf("expected warning on stderr, got %q", stderr.String())
	}

	// Match: quiet success
	stderr.Reset()
	err = checkCreateIntentAgainstExisting(target, connectCreateOpts{port: "8080"}, &stderr)
	if err != nil {
		t.Fatalf("matching port should not error: %v", err)
	}
	if stderr.Len() != 0 {
		t.Fatalf("matching port should be quiet, got %q", stderr.String())
	}
}

func TestBuildConnectRunArgs(t *testing.T) {
	got := buildConnectRunArgs("demo", true, connectCreateOpts{port: "9000"})
	want := []string{"run", "--daemon", "--keep-alive", "--name", "demo", "--port", "9000"}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("buildConnectRunArgs = %v, want %v", got, want)
	}

	got = buildConnectRunArgs("", false, connectCreateOpts{})
	want = []string{"run", "--daemon"}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("minimal buildConnectRunArgs = %v, want %v", got, want)
	}

	got = buildConnectRunArgs("", false, connectCreateOpts{port: "NEXT"})
	want = []string{"run", "--daemon", "--port", "NEXT"}
	if strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("NEXT port buildConnectRunArgs = %v, want %v", got, want)
	}
}

func TestHostPortFromInspect(t *testing.T) {
	// Live NetworkSettings wins
	data := inspectData{}
	data.NetworkSettings.Ports = map[string][]struct {
		HostPort string `json:"HostPort"`
	}{
		"10000/tcp": {{HostPort: "9000"}},
	}
	if got := hostPortFromInspect(data); got != "9000" {
		t.Fatalf("NetworkSettings port = %q, want 9000", got)
	}

	// Stopped: fall back to HostConfig
	data = inspectData{}
	data.HostConfig.PortBindings = map[string][]struct {
		HostPort string `json:"HostPort"`
	}{
		"10000/tcp": {{HostPort: "8080"}},
	}
	if got := hostPortFromInspect(data); got != "8080" {
		t.Fatalf("HostConfig port = %q, want 8080", got)
	}

	// Public TLS container port
	data = inspectData{}
	data.NetworkSettings.Ports = map[string][]struct {
		HostPort string `json:"HostPort"`
	}{
		"10443/tcp": {{HostPort: "443"}},
	}
	if got := hostPortFromInspect(data); got != "443" {
		t.Fatalf("public TLS port = %q, want 443", got)
	}
}

func TestNewlyCreatedContainer(t *testing.T) {
	pre := []managedContainer{
		{Name: "myproj-10000", State: "running"},
		{Name: "other", State: "running"},
	}

	// Exactly one new running booth appeared.
	post := append([]managedContainer{}, pre...)
	post = append(post, managedContainer{Name: "myproj-11000", State: "running"})
	got, err := newlyCreatedContainer(pre, post)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Name != "myproj-11000" {
		t.Errorf("got %q, want myproj-11000", got.Name)
	}

	// No new running booth -> error.
	if _, err := newlyCreatedContainer(pre, pre); err == nil {
		t.Error("expected error when no new container appeared")
	}

	// A new booth that is not running is ignored -> treated as none.
	postStopped := append([]managedContainer{}, pre...)
	postStopped = append(postStopped, managedContainer{Name: "myproj-11000", State: "created"})
	if _, err := newlyCreatedContainer(pre, postStopped); err == nil {
		t.Error("expected error when the only new container is not running")
	}

	// Multiple new running booths -> ambiguous error.
	postMulti := append([]managedContainer{}, pre...)
	postMulti = append(postMulti,
		managedContainer{Name: "myproj-11000", State: "running"},
		managedContainer{Name: "myproj-12000", State: "running"},
	)
	if _, err := newlyCreatedContainer(pre, postMulti); err == nil {
		t.Error("expected error when multiple new containers appeared")
	}
}
