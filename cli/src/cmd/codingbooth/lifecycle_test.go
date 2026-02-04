// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"strings"
	"testing"
)

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
