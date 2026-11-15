// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGitHubStarPrompt_OnUntilClicked(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "codingbooth", "github-star")
	if got := githubStarPrompt("", marker); got != "on" {
		t.Fatalf("no marker: got %q, want on", got)
	}
	if err := os.MkdirAll(filepath.Dir(marker), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(marker, nil, 0644); err != nil {
		t.Fatal(err)
	}
	if got := githubStarPrompt("", marker); got != "done" {
		t.Fatalf("marker: got %q, want done", got)
	}
	if got := githubStarPrompt("", ""); got != "on" {
		t.Fatalf("unknown config dir: got %q, want on", got)
	}
}

func TestGitHubStarPrompt_OffWins(t *testing.T) {
	for _, setting := range []string{"off", "OFF", " false ", "no", "0"} {
		if got := githubStarPrompt(setting, ""); got != "off" {
			t.Errorf("CB_STAR_PROMPT=%q: got %q, want off", setting, got)
		}
	}
	if got := githubStarPrompt("on", ""); got != "on" {
		t.Errorf("CB_STAR_PROMPT=on: got %q, want on", got)
	}
}

func TestPromoteGitHubStar(t *testing.T) {
	boothDir := filepath.Join(t.TempDir(), ".booth")
	marker := filepath.Join(t.TempDir(), "codingbooth", "github-star")
	if err := os.MkdirAll(filepath.Join(boothDir, ".tmp"), 0755); err != nil {
		t.Fatal(err)
	}

	promoteGitHubStarTo(boothDir, marker)
	if _, err := os.Stat(marker); err == nil {
		t.Fatal("marker written although the link was not clicked")
	}

	if err := os.WriteFile(filepath.Join(boothDir, ".tmp", GitHubStarTmpName), []byte("clicked\n"), 0644); err != nil {
		t.Fatal(err)
	}
	promoteGitHubStarTo(boothDir, marker)
	if _, err := os.Stat(marker); err != nil {
		t.Fatalf("click not promoted: %v", err)
	}
	if got := githubStarPrompt("", marker); got != "done" {
		t.Fatalf("after promotion: got %q, want done", got)
	}
}
