// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package githubstar

import (
	"os"
	"path/filepath"
	"testing"
)

func TestGitHubStarPrompt_OnUntilClicked(t *testing.T) {
	marker := filepath.Join(t.TempDir(), "codingbooth", "github-star")
	if got := prompt("", marker); got != "on" {
		t.Fatalf("no marker: got %q, want on", got)
	}
	if err := os.MkdirAll(filepath.Dir(marker), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(marker, nil, 0644); err != nil {
		t.Fatal(err)
	}
	if got := prompt("", marker); got != "done" {
		t.Fatalf("marker: got %q, want done", got)
	}
	if got := prompt("", ""); got != "on" {
		t.Fatalf("unknown config dir: got %q, want on", got)
	}
}

func TestGitHubStarPrompt_OffWins(t *testing.T) {
	for _, setting := range []string{"off", "OFF", " false ", "no", "0"} {
		if got := prompt(setting, ""); got != "off" {
			t.Errorf("CB_STAR_PROMPT=%q: got %q, want off", setting, got)
		}
	}
	if got := prompt("on", ""); got != "on" {
		t.Errorf("CB_STAR_PROMPT=on: got %q, want on", got)
	}
}

func TestPromote(t *testing.T) {
	boothDir := filepath.Join(t.TempDir(), ".booth")
	marker := filepath.Join(t.TempDir(), "codingbooth", "github-star")
	if err := os.MkdirAll(filepath.Join(boothDir, ".tmp"), 0755); err != nil {
		t.Fatal(err)
	}

	promoteTo(boothDir, marker)
	if _, err := os.Stat(marker); err == nil {
		t.Fatal("marker written although the link was not clicked")
	}

	if err := os.WriteFile(filepath.Join(boothDir, ".tmp", TmpName), []byte("clicked\n"), 0644); err != nil {
		t.Fatal(err)
	}
	promoteTo(boothDir, marker)
	if _, err := os.Stat(marker); err != nil {
		t.Fatalf("click not promoted: %v", err)
	}
	if got := prompt("", marker); got != "done" {
		t.Fatalf("after promotion: got %q, want done", got)
	}
}

// XDG_CONFIG_HOME wins on every OS (os.UserConfigDir ignores it on macOS); a relative
// one is ignored, as the XDG spec says, and the OS folder is used instead.
func TestMarkerPathFrom(t *testing.T) {
	osDir := func() (string, error) { return "/os/config", nil }
	noDir := func() (string, error) { return "", os.ErrNotExist }
	cases := []struct {
		name, xdg string
		dir       func() (string, error)
		want      string
	}{
		{"xdg set", "/xdg", osDir, filepath.Join("/xdg", "codingbooth", "github-star")},
		{"xdg unset", "", osDir, filepath.Join("/os/config", "codingbooth", "github-star")},
		{"xdg relative", "rel", osDir, filepath.Join("/os/config", "codingbooth", "github-star")},
		{"xdg set, no os folder", "/xdg", noDir, filepath.Join("/xdg", "codingbooth", "github-star")},
		{"nothing known", "", noDir, ""},
	}
	for _, c := range cases {
		if got := markerPathFrom(c.xdg, c.dir); got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
}
