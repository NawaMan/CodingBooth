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
