// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestVersionOlder(t *testing.T) {
	cases := []struct {
		have, want string
		older      bool
	}{
		{"0.77.0", "0.82.0", true},
		{"0.82.0", "0.82.0", false},
		{"0.83.0", "0.82.0", false},
		{"0.82.0--rc1", "0.82.0", false}, // the suffix is not compared
		{"0.82.0", "0.83.0--booth-dash", true},
		{"0.9.0", "0.10.0", true}, // numbers, not text
		{"v1.2.3", "1.2.4", true},
		{"", "0.82.0", false},       // unknown is never older
		{"0.82.0", "latest", false}, // nor against something unparsable
	}
	for _, c := range cases {
		if got := versionOlder(c.have, c.want); got != c.older {
			t.Errorf("versionOlder(%q, %q) = %v, want %v", c.have, c.want, got, c.older)
		}
	}
}

func TestLockVersion(t *testing.T) {
	lock := "version=0.82.0\ndownloaded_at=2026-11-10T17:09:14Z\ncache=shared\n"
	if got := lockVersion(bufio.NewScanner(strings.NewReader(lock))); got != "0.82.0" {
		t.Errorf("lockVersion = %q", got)
	}
	if got := lockVersion(bufio.NewScanner(strings.NewReader("cache=shared\n"))); got != "" {
		t.Errorf("no version line: %q", got)
	}
}

func TestFreshnessUsesProjectLockElseCLI(t *testing.T) {
	pinned := t.TempDir()
	if err := os.MkdirAll(filepath.Join(pinned, ".booth", "tools"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pinned, ".booth", "tools", "codingbooth.lock"), []byte("version=0.82.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	booths := []Booth{
		{Name: "old", Engine: "docker", CodePath: pinned, Version: "0.77.0"},
		{Name: "pinned", Engine: "docker", CodePath: pinned, Version: "0.82.0"},
		{Name: "loose", Engine: "docker", CodePath: t.TempDir(), Version: "0.82.0"},
	}
	got := Freshness(booths, "0.83.0--booth-dash")
	if f := got["old@docker"]; !f.Older || f.Want != "0.82.0" {
		t.Errorf("old = %+v, want older than the lock's 0.82.0", f)
	}
	if f := got["pinned@docker"]; f.Older {
		t.Errorf("pinned = %+v: at its lock's version, it is not older", f)
	}
	if f := got["loose@docker"]; !f.Older || f.Want != "0.83.0--booth-dash" {
		t.Errorf("loose = %+v, want older than the CLI with no lock", f)
	}
}

func TestTTLCacheKeepsAnswersForAWhile(t *testing.T) {
	now := time.Date(2026, 11, 11, 12, 0, 0, 0, time.UTC)
	c := &ttlCache{entries: map[string]ttlEntry{}, now: func() time.Time { return now }}
	loads := 0
	load := func() (string, bool) { loads++; return "sha256:a", true }
	c.get("k", load)
	c.get("k", load)
	if loads != 1 {
		t.Fatalf("loads = %d within the TTL", loads)
	}
	now = now.Add(imageCacheTTL)
	if v, ok := c.get("k", load); loads != 2 || v != "sha256:a" || !ok {
		t.Errorf("after the TTL: loads %d, %q %v", loads, v, ok)
	}
}
