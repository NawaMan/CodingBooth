// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package justinit

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestStarterMatchesDocs keeps the embedded starter and the copy the docs link to
// on GitHub byte-identical. Edit both, or this fails.
func TestStarterMatchesDocs(t *testing.T) {
	doc := filepath.Join("..", "..", "..", "..", "docs", "just", "Justfile")
	data, err := os.ReadFile(doc)
	if err != nil {
		t.Fatalf("reading %s: %v", doc, err)
	}
	if string(data) != Starter {
		t.Error("docs/just/Justfile has drifted from cli/src/pkg/justinit/Justfile; they must be identical")
	}
}

func TestFindJustfile(t *testing.T) {
	dir := t.TempDir()
	if got := FindJustfile(dir); got != "" {
		t.Errorf("empty folder: got %q", got)
	}
	for _, name := range justfileNames {
		d := t.TempDir()
		mustWrite(t, filepath.Join(d, name), "x")
		if got := FindJustfile(d); got != filepath.Join(d, name) {
			t.Errorf("with %s: got %q", name, got)
		}
	}
	// A folder named Justfile is not one.
	d := t.TempDir()
	if err := os.Mkdir(filepath.Join(d, "Justfile"), 0755); err != nil {
		t.Fatal(err)
	}
	if got := FindJustfile(d); got != "" {
		t.Errorf("folder named Justfile: got %q", got)
	}
}

func TestBackupNeverOverwrites(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "Justfile")
	for i, want := range []string{path + ".bak", path + ".bak.1", path + ".bak.2"} {
		content := string(rune('a' + i))
		mustWrite(t, path, content)
		got, err := Backup(path)
		if err != nil {
			t.Fatal(err)
		}
		if got != want {
			t.Errorf("backup %d went to %q, want %q", i, got, want)
		}
		assertFile(t, got, content)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Error("the original is still in place after a backup")
	}
}

func TestWrite(t *testing.T) {
	dir := t.TempDir()
	path, err := Write(dir)
	if err != nil {
		t.Fatal(err)
	}
	if path != filepath.Join(dir, "Justfile") {
		t.Errorf("path = %q", path)
	}
	assertFile(t, path, Starter)

	// A second write refuses rather than overwrite, whatever the existing name.
	d := t.TempDir()
	mustWrite(t, filepath.Join(d, "justfile"), "mine")
	if _, err := Write(d); err == nil {
		t.Error("Write over an existing justfile should refuse")
	}
	assertFile(t, filepath.Join(d, "justfile"), "mine")
}

func TestIsFirstConfigure(t *testing.T) {
	dir := t.TempDir()
	if !IsFirstConfigure(dir) {
		t.Fatal("an empty folder is a first configure")
	}
	// The wrapper creates .booth/ with its own files before the CLI runs.
	if err := os.MkdirAll(filepath.Join(dir, ".booth", "tools"), 0755); err != nil {
		t.Fatal(err)
	}
	mustWrite(t, filepath.Join(dir, ".booth", ".gitignore"), "x")
	mustWrite(t, filepath.Join(dir, ".booth", "tools", "codingbooth.lock"), "0.80.0")
	if !IsFirstConfigure(dir) {
		t.Fatal("a .booth/ holding only the wrapper's files is still a first configure")
	}
	for _, name := range []string{"Boothfile", "config.toml"} {
		d := t.TempDir()
		if err := os.MkdirAll(filepath.Join(d, ".booth"), 0755); err != nil {
			t.Fatal(err)
		}
		mustWrite(t, filepath.Join(d, ".booth", name), "x")
		if IsFirstConfigure(d) {
			t.Errorf("a booth with %s is not a first configure", name)
		}
	}
}

func TestWriteIfMissing(t *testing.T) {
	dir := t.TempDir()
	path, err := WriteIfMissing(dir)
	if err != nil || path != filepath.Join(dir, "Justfile") {
		t.Fatalf("path=%q err=%v", path, err)
	}
	assertFile(t, path, Starter)

	d := t.TempDir()
	mustWrite(t, filepath.Join(d, ".justfile"), "mine")
	path, err = WriteIfMissing(d)
	if err != nil || path != "" {
		t.Errorf("beside an existing .justfile: path=%q err=%v, want nothing written", path, err)
	}
	assertFile(t, filepath.Join(d, ".justfile"), "mine")
}

// TestStarterRuns has the real just parse the starter and checks where each line
// goes, on the host and inside a booth. Skipped where just is not installed.
func TestStarterRuns(t *testing.T) {
	justBin, err := exec.LookPath("just")
	if err != nil {
		t.Skip("just is not on PATH")
	}
	dir := filepath.Join(t.TempDir(), "a project")
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	if _, err := Write(dir); err != nil {
		t.Fatal(err)
	}

	run := func(inBooth bool, args ...string) (string, error) {
		cmd := exec.Command(justBin, args...)
		cmd.Dir = dir
		var env []string
		for _, kv := range os.Environ() {
			if !strings.HasPrefix(kv, "BOOTH_CONTAINER_NAME=") {
				env = append(env, kv)
			}
		}
		if inBooth {
			env = append(env, "BOOTH_CONTAINER_NAME=test-booth")
		}
		cmd.Env = env
		out, err := cmd.CombinedOutput()
		return string(out), err
	}

	if out, err := run(false, "--list"); err != nil || !strings.Contains(out, "info") || !strings.Contains(out, "shell") {
		t.Fatalf("just --list: %v\n%s", err, out)
	}
	if out, err := run(false, "--dry-run", "info"); err != nil || !strings.Contains(out, "./booth exec --run -- booth--info") {
		t.Errorf("host info: err=%v out=%q, want it handed to ./booth exec --run", err, out)
	}
	if out, err := run(true, "--dry-run", "info"); err != nil || strings.Contains(out, "exec --run") || !strings.Contains(out, "booth--info") {
		t.Errorf("in-booth info: err=%v out=%q, want a bare booth--info", err, out)
	}
	if out, err := run(false, "--dry-run", "shell"); err != nil || strings.Contains(out, "exit 2") {
		t.Errorf("host shell: err=%v out=%q, want it run as is", err, out)
	}
	if out, err := run(true, "shell"); err == nil || !strings.Contains(out, "runs on the host") {
		t.Errorf("in-booth shell: err=%v out=%q, want a host-only refusal", err, out)
	}
}

func mustWrite(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

func assertFile(t *testing.T, path, want string) {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v", path, err)
	}
	if string(data) != want {
		t.Errorf("%s = %q, want %q", path, data, want)
	}
}
