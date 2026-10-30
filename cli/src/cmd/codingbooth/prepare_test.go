// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bytes"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/prepare"
)

func TestParsePrepareArgs(t *testing.T) {
	var stderr bytes.Buffer
	o, _, ok := parsePrepareArgs([]string{"ubuntu", "--variant", "xfce", "--add-user=dev", "--source", "/src", "--report=/r.txt", "--code", "/p", "-y"}, &stderr)
	if !ok || o.Target != prepare.Ubuntu || o.Variant != "xfce" || o.AddUser != "dev" || o.Source != "/src" ||
		o.Report != "/r.txt" || o.ProjectDir != "/p" || !o.Yes {
		t.Fatalf("parsed %+v ok=%v stderr=%s", o, ok, stderr.String())
	}
	if o, _, ok := parsePrepareArgs([]string{"gha"}, &stderr); !ok || o.Target != prepare.GHA || o.ProjectDir != "." {
		t.Errorf("gha: %+v %v", o, ok)
	}

	for _, bad := range [][]string{{}, {"host"}, {"gha", "ubuntu"}, {"gha", "--bogus"}, {"ubuntu", "--variant"}} {
		stderr.Reset()
		if _, code, ok := parsePrepareArgs(bad, &stderr); ok || code != 2 || !strings.Contains(stderr.String(), "Error") {
			t.Errorf("%v: want a usage error, got ok=%v code=%d stderr=%q", bad, ok, code, stderr.String())
		}
	}
}
