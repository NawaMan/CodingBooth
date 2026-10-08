// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/justinit"
)

func runJustInitTest(t *testing.T, args []string, stdin string, interactive bool) (int, string, string) {
	t.Helper()
	var out, errOut bytes.Buffer
	code := justInit(args, strings.NewReader(stdin), &out, &errOut, interactive)
	return code, out.String(), errOut.String()
}

func readOrEmpty(path string) string {
	data, _ := os.ReadFile(path)
	return string(data)
}

func TestJustInitWritesStarter(t *testing.T) {
	dir := t.TempDir()
	code, out, _ := runJustInitTest(t, []string{dir}, "", false)
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	if readOrEmpty(filepath.Join(dir, "Justfile")) != justinit.Starter {
		t.Error("Justfile is not the starter")
	}
	if !strings.Contains(out, "Created") {
		t.Errorf("stdout = %q", out)
	}
}

func TestJustInitCodeFlag(t *testing.T) {
	// The shell-config function appends --code <root> when run from a subfolder.
	dir := t.TempDir()
	if code, _, _ := runJustInitTest(t, []string{"--code", dir}, "", false); code != 0 {
		t.Fatalf("exit %d", code)
	}
	if readOrEmpty(filepath.Join(dir, "Justfile")) != justinit.Starter {
		t.Error("--code did not pick the folder")
	}
}

func TestJustInitExistingNonInteractiveRefuses(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "Justfile"), []byte("mine"), 0644)
	code, _, errOut := runJustInitTest(t, []string{dir}, "", false)
	if code == 0 || !strings.Contains(errOut, "--yes") {
		t.Errorf("exit %d, stderr %q; want a refusal naming --yes", code, errOut)
	}
	if readOrEmpty(filepath.Join(dir, "Justfile")) != "mine" {
		t.Error("the existing Justfile was touched")
	}
}

func TestJustInitExistingAsksAndDeclines(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "Justfile"), []byte("mine"), 0644)
	code, _, errOut := runJustInitTest(t, []string{dir}, "n\n", true)
	if code == 0 || !strings.Contains(errOut, "Back it up to Justfile.bak") {
		t.Errorf("exit %d, stderr %q; want the backup question, then a no", code, errOut)
	}
	if readOrEmpty(filepath.Join(dir, "Justfile")) != "mine" {
		t.Error("the existing Justfile was touched after a no")
	}
}

func TestJustInitExistingAsksAndBacksUp(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "justfile"), []byte("mine"), 0644)
	if code, _, _ := runJustInitTest(t, []string{dir}, "y\n", true); code != 0 {
		t.Fatalf("exit %d", code)
	}
	if readOrEmpty(filepath.Join(dir, "justfile.bak")) != "mine" {
		t.Error("the old justfile was not backed up to justfile.bak")
	}
	if readOrEmpty(filepath.Join(dir, "Justfile")) != justinit.Starter {
		t.Error("the starter was not written")
	}
}

func TestJustInitYesKeepsEarlierBackups(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "Justfile.bak"), []byte("older"), 0644)
	os.WriteFile(filepath.Join(dir, "Justfile"), []byte("mine"), 0644)
	if code, _, _ := runJustInitTest(t, []string{dir, "--yes"}, "", false); code != 0 {
		t.Fatalf("exit %d", code)
	}
	if readOrEmpty(filepath.Join(dir, "Justfile.bak")) != "older" {
		t.Error("an earlier backup was overwritten")
	}
	if readOrEmpty(filepath.Join(dir, "Justfile.bak.1")) != "mine" {
		t.Error("the Justfile was not backed up to Justfile.bak.1")
	}
}

func TestJustInitBadArgs(t *testing.T) {
	if code, _, _ := runJustInitTest(t, []string{"--nope"}, "", false); code != 2 {
		t.Errorf("unknown option: exit %d, want 2", code)
	}
	if code, _, _ := runJustInitTest(t, []string{filepath.Join(t.TempDir(), "missing")}, "", false); code != 1 {
		t.Errorf("missing folder: exit %d, want 1", code)
	}
}
