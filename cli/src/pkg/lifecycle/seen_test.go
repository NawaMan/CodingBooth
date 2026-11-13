// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// project makes a folder with a .booth in it.
func project(t *testing.T, root, name string) string {
	t.Helper()
	dir := filepath.Join(root, name)
	if err := os.MkdirAll(filepath.Join(dir, ".booth"), 0o755); err != nil {
		t.Fatal(err)
	}
	return dir
}

func names(booths []Booth) []string {
	out := []string{}
	for _, b := range booths {
		out = append(out, b.Name+"@"+b.Engine+":"+b.State)
	}
	return out
}

func TestSeenReturnsABoothOnceItsContainerIsGone(t *testing.T) {
	root := t.TempDir()
	app := project(t, root, "app")
	at := time.Date(2026, 11, 12, 10, 0, 0, 0, time.UTC)
	s := Seen{Path: filepath.Join(root, "cache", "seen.json"), Now: func() time.Time { return at }}

	live := []Booth{{Name: "app", Engine: "docker", State: "running", Variant: "base", CodePath: app}}
	if got := s.Remember(live, nil); len(got) != 0 {
		t.Fatalf("a live booth is not gone: %v", names(got))
	}
	got := s.Remember(nil, nil)
	if len(got) != 1 || got[0].Name != "app" || !got[0].Gone() || got[0].CodePath != app ||
		got[0].Variant != "base" || got[0].FinishedAt != "2026-11-12T10:00:00Z" {
		t.Fatalf("got %+v", got)
	}
	// Remembered across runs: a new store on the same file.
	if got := (Seen{Path: s.Path}).Remember(nil, nil); len(got) != 1 {
		t.Fatalf("not kept in the file: %v", names(got))
	}
}

func TestSeenForgetsABoothWhoseFolderOrBoothDirIsGone(t *testing.T) {
	root := t.TempDir()
	noBooth, noFolder, kept := project(t, root, "a"), project(t, root, "b"), project(t, root, "c")
	s := Seen{Path: filepath.Join(root, "seen.json")}
	s.Remember([]Booth{
		{Name: "a", Engine: "docker", CodePath: noBooth},
		{Name: "b", Engine: "docker", CodePath: noFolder},
		{Name: "c", Engine: "docker", CodePath: kept},
	}, nil)
	os.RemoveAll(filepath.Join(noBooth, ".booth"))
	os.RemoveAll(noFolder)

	if got := names(s.Remember(nil, nil)); len(got) != 1 || got[0] != "c@docker:gone" {
		t.Fatalf("got %v", got)
	}
	// Dropped from the file, not only hidden: the .booth coming back does not
	// bring the booth back.
	os.MkdirAll(filepath.Join(noBooth, ".booth"), 0o755)
	if got := names(s.Remember(nil, nil)); len(got) != 1 {
		t.Fatalf("got %v", got)
	}
}

func TestSeenUsesAnExpressBoothsOwnBoothDir(t *testing.T) {
	root := t.TempDir()
	code := filepath.Join(root, "code")
	os.MkdirAll(code, 0o755) // no .booth of its own
	boothDir := filepath.Join(root, "express", "x")
	os.MkdirAll(boothDir, 0o755)
	s := Seen{Path: filepath.Join(root, "seen.json")}
	s.Remember([]Booth{{Name: "x", Engine: "docker", CodePath: code, BoothDir: boothDir}}, nil)
	if got := s.Remember(nil, nil); len(got) != 1 || got[0].BoothDir != boothDir {
		t.Fatalf("got %+v", got)
	}
}

func TestSeenForget(t *testing.T) {
	root := t.TempDir()
	s := Seen{Path: filepath.Join(root, "seen.json")}
	s.Remember([]Booth{
		{Name: "a", Engine: "docker", CodePath: project(t, root, "a")},
		{Name: "a", Engine: "podman", CodePath: project(t, root, "a2")},
	}, nil)
	if err := s.Forget("a", "docker"); err != nil {
		t.Fatal(err)
	}
	if got := names(s.Remember(nil, nil)); len(got) != 1 || got[0] != "a@podman:gone" {
		t.Fatalf("got %v", got)
	}
}

func TestSeenHidesBoothsOfAnEngineThatDidNotAnswerOrIsNotShown(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "seen.json")
	(Seen{Path: path}).Remember([]Booth{
		{Name: "d", Engine: "docker", CodePath: project(t, root, "d")},
		{Name: "p", Engine: "podman", CodePath: project(t, root, "p")},
	}, nil)

	got := names((Seen{Path: path}).Remember(nil, []string{"Warning: podman is not responding"}))
	if len(got) != 1 || got[0] != "d@docker:gone" {
		t.Fatalf("with a podman warning: %v", got)
	}
	got = names((Seen{Path: path, Engine: "podman"}).Remember(nil, nil))
	if len(got) != 1 || got[0] != "p@podman:gone" {
		t.Fatalf("--engine podman: %v", got)
	}
	// Hidden, not forgotten.
	if got := names((Seen{Path: path}).Remember(nil, nil)); len(got) != 2 {
		t.Fatalf("got %v", got)
	}
}

func TestSeenSurvivesAMissingOrBrokenFile(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "seen.json")
	os.WriteFile(path, []byte("not json"), 0o644)
	s := Seen{Path: path}
	if got := s.Remember(nil, nil); len(got) != 0 {
		t.Fatalf("got %v", names(got))
	}
	s.Remember([]Booth{{Name: "a", Engine: "docker", CodePath: project(t, root, "a")}}, nil)
	if got := s.Remember(nil, nil); len(got) != 1 {
		t.Fatalf("a broken file is not replaced: %v", names(got))
	}
	if got := (Seen{}).Remember([]Booth{{Name: "a", CodePath: root}}, nil); got != nil {
		t.Fatalf("no path remembers nothing: %v", names(got))
	}
}
