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
