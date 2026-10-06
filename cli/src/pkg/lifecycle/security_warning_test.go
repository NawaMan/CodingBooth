// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/hostescape"
)

func TestSecurityWarning_FromLabel(t *testing.T) {
	reasons := []hostescape.Reason{{Kind: hostescape.KindDind, What: "--dind (privileged Docker-in-Docker sidecar)"}}
	target := managedContainer{Name: "web", SecurityWarning: hostescape.DecodeLabel(hostescape.EncodeLabel(reasons))}
	got := securityWarning(target)
	for _, want := range []string{"--dind (privileged", hostescape.Link(hostescape.KindDind), "This booth was created with these settings."} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	if strings.Contains(got, "[y/N]") {
		t.Errorf("starting an existing booth must not ask, got:\n%s", got)
	}
}

func TestSecurityWarning_NoLabel_Silent(t *testing.T) {
	if got := securityWarning(managedContainer{Name: "web"}); got != "" {
		t.Fatalf("a booth created without reasons (or before the label existed) prints nothing, got %q", got)
	}
}
