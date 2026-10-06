// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestWantsLifecycleLog(t *testing.T) {
	if got, err := wantsLifecycleLog(logsOptions{services: []string{"lifecycle"}}); !got || err != nil {
		t.Errorf("lifecycle alone: got %v, %v", got, err)
	}
	if got, err := wantsLifecycleLog(logsOptions{services: []string{"nginx-access"}}); got || err != nil {
		t.Errorf("other service: got %v, %v", got, err)
	}
	if _, err := wantsLifecycleLog(logsOptions{services: []string{"lifecycle", "startups"}}); err == nil {
		t.Errorf("mixing lifecycle with an in-booth service should be refused")
	}
}

func TestLifecycleLogCodePath(t *testing.T) {
	containers := []managedContainer{{Name: "demo", CodePath: "/work/demo"}, {Name: "bare"}}

	if got, _ := lifecycleLogCodePath(logsOptions{}, nil, "/here"); got != "/here" {
		t.Errorf("default = %q, want the current folder", got)
	}
	abs, _ := filepath.Abs("some/dir")
	if got, _ := lifecycleLogCodePath(logsOptions{code: "some/dir"}, nil, "/here"); got != abs {
		t.Errorf("--code = %q, want %q", got, abs)
	}
	if got, _ := lifecycleLogCodePath(logsOptions{name: "demo"}, containers, "/here"); got != "/work/demo" {
		t.Errorf("--name = %q, want the booth's code folder", got)
	}
	if _, err := lifecycleLogCodePath(logsOptions{name: "gone"}, containers, "/here"); err == nil || !strings.Contains(err.Error(), "--code") {
		t.Errorf("missing booth: want an error pointing at --code, got %v", err)
	}
	if _, err := lifecycleLogCodePath(logsOptions{name: "bare"}, containers, "/here"); err == nil {
		t.Errorf("booth without a code path: want an error")
	}
}

func TestShowLifecycleLogReadsTheHostFile(t *testing.T) {
	code := t.TempDir()
	os.MkdirAll(filepath.Join(code, ".booth", ".tmp"), 0755)
	os.WriteFile(filepath.Join(code, ".booth", ".tmp", "lifecycle.log"), []byte("a started\nb exited status=0\n"), 0644)

	var out, errOut bytes.Buffer
	if err := Logs([]string{"--code", code, "-n", "1", "lifecycle"}, &out, &errOut); err != nil {
		t.Fatalf("Logs: %v (%s)", err, errOut.String())
	}
	if out.String() != "b exited status=0\n" {
		t.Errorf("output = %q", out.String())
	}
}

func TestShowLifecycleLogMissingFile(t *testing.T) {
	code := t.TempDir()
	var out, errOut bytes.Buffer
	err := Logs([]string{"--code", code, "lifecycle"}, &out, &errOut)
	if err == nil || ExitCode(err) != 1 || !strings.Contains(err.Error(), "No lifecycle log") {
		t.Errorf("want exit 1 naming the missing log, got %v", err)
	}
}

func TestCopyAppendedRestartsAfterTrim(t *testing.T) {
	path := filepath.Join(t.TempDir(), "lifecycle.log")
	os.WriteFile(path, []byte("one\ntwo\n"), 0644)
	var out bytes.Buffer
	offset := copyAppended(path, 4, &out)
	if out.String() != "two\n" || offset != 8 {
		t.Errorf("append: %q, offset %d", out.String(), offset)
	}
	os.WriteFile(path, []byte("new\n"), 0644) // shrank: trimmed
	out.Reset()
	if offset = copyAppended(path, offset, &out); out.String() != "new\n" || offset != 4 {
		t.Errorf("after shrink: %q, offset %d", out.String(), offset)
	}
}
