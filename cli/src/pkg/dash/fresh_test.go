// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

func versioned(name, version string) lifecycle.Booth {
	b := running(name)
	b.Version = version
	b.ImageRef = "codingbooth-local:" + name
	return b
}

func TestVersionColumnMarksBoothsBehind(t *testing.T) {
	f := &fakeDeps{}
	m := newModel(f.deps())
	next, _ := m.Update(snapshotMsg{seq: 1,
		booths: []lifecycle.Booth{versioned("old", "0.77.0"), versioned("ok", "0.82.0"), versioned("redone", "0.82.0")},
		fresh: map[string]lifecycle.Fresh{
			"old@docker":    {Want: "0.82.0", Older: true},
			"ok@docker":     {Want: "0.82.0"},
			"redone@docker": {Want: "0.82.0", Rebuilt: true},
		}})
	m = next.(model)
	view := stripANSI(m.View())
	for _, want := range []string{"VERSION", "0.77.0 → 0.82.0", "0.82.0 (rebuilt)"} {
		if !strings.Contains(view, want) {
			t.Errorf("view lacks %q:\n%s", want, view)
		}
	}
	if !m.behind(m.rows[0]) || m.behind(m.rows[1]) || !m.behind(m.rows[2]) {
		t.Errorf("behind = %v %v %v, want old and redone", m.behind(m.rows[0]), m.behind(m.rows[1]), m.behind(m.rows[2]))
	}
	// Each cell is styled on its own: the plain text is the same as before.
	if !strings.Contains(view, "› old") {
		t.Errorf("cursor row lost its marker:\n%s", view)
	}
}

func TestImageRowSaysHowToUpdate(t *testing.T) {
	f := &fakeDeps{}
	m := newModel(f.deps())
	m.fresh = map[string]lifecycle.Fresh{"old@docker": {Want: "0.82.0", Older: true, Rebuilt: true}}
	got := m.imageText(versioned("old", "0.77.0"))
	for _, want := range []string{
		"built with 0.77.0; its project now builds 0.82.0",
		"its image codingbooth-local:old was rebuilt since",
		"booth remove --force --name old (a persisted home goes with it)",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("Image row lacks %q: %q", want, got)
		}
	}
	if got := m.imageText(versioned("fine", "0.82.0")); got != "up to date (0.82.0)" {
		t.Errorf("up-to-date row = %q", got)
	}
}
