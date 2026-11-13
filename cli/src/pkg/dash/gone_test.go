// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"reflect"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

func goneBooth() lifecycle.Booth {
	return lifecycle.Booth{Name: "old", Engine: "docker", State: lifecycle.StateGone, CodePath: "/home/u/dev/old"}
}

// goneModel shows one gone booth (no repository) under its live neighbour.
func goneModel(f *fakeDeps) model {
	m := newModel(f.deps())
	next, _ := m.Update(snapshotMsg{seq: 1, booths: []lifecycle.Booth{running("web"), goneBooth()}})
	return next.(model)
}

func TestFetchAddsTheRememberedBoothsAndFindsTheirRepos(t *testing.T) {
	var sawLive []lifecycle.Booth
	var sawWarnings, reposFor []string
	deps := (&fakeDeps{snapshot: []lifecycle.Booth{running("web")}}).deps()
	deps.Snapshot = func() ([]lifecycle.Booth, []string, error) {
		return []lifecycle.Booth{running("web")}, []string{"podman: down"}, nil
	}
	deps.Remembered = func(live []lifecycle.Booth, warnings []string) []lifecycle.Booth {
		sawLive, sawWarnings = live, warnings
		return []lifecycle.Booth{goneBooth()}
	}
	deps.Repos = func(booths []lifecycle.Booth) []lifecycle.Repo {
		for _, b := range booths {
			reposFor = append(reposFor, b.Name)
		}
		return nil
	}
	deps.Freshness = func(booths []lifecycle.Booth) map[string]lifecycle.Fresh {
		for _, b := range booths {
			if b.Gone() {
				t.Errorf("freshness asked about gone booth %s", b.Name)
			}
		}
		return nil
	}
	msg := newModel(deps).fetch(1)().(snapshotMsg)
	if len(sawLive) != 1 || sawLive[0].Name != "web" || !reflect.DeepEqual(sawWarnings, []string{"podman: down"}) {
		t.Fatalf("Remembered got live %v warnings %v", sawLive, sawWarnings)
	}
	if !reflect.DeepEqual(reposFor, []string{"web", "old"}) {
		t.Fatalf("repos looked for %v; the gone booth's folder must count", reposFor)
	}
	if len(msg.booths) != 2 || !msg.booths[1].Gone() {
		t.Fatalf("booths %+v", msg.booths)
	}
}

func TestGoneBoothShowsAsGoneAndCounted(t *testing.T) {
	m := goneModel(&fakeDeps{})
	m.width, m.height = 120, 30
	view := m.View()
	if !strings.Contains(view, "Gone") || !strings.Contains(view, "1 booth · 1 gone") {
		t.Fatalf("view:\n%s", view)
	}
}

func TestEnterOnGoneBoothOffersARunShellInItsFolder(t *testing.T) {
	f := &fakeDeps{}
	m, _ := press(t, goneModel(f), "down", "enter")
	if m.confirm == nil || !strings.Contains(m.confirm.plan.Confirm, "old has no container") {
		t.Fatalf("confirm %+v status %q", m.confirm, m.status)
	}
	m, cmd := press(t, m, "y")
	if cmd == nil {
		t.Fatal("y must run the shell")
	}
	want := []string{"shell", "--run", "--name", "old", "--engine", "docker", "--code", "/home/u/dev/old"}
	if len(f.execed) != 1 || !reflect.DeepEqual(f.execed[0], want) || f.execedIn[0] != "/home/u/dev/old" {
		t.Fatalf("ran %v in %v", f.execed, f.execedIn)
	}
}

func TestDeleteOnGoneBoothOnlyForgetsIt(t *testing.T) {
	f := &fakeDeps{}
	var forgot []string
	deps := f.deps()
	deps.Forget = func(b lifecycle.Booth) error { forgot = append(forgot, b.Name+"@"+b.Engine); return nil }
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: []lifecycle.Booth{running("web"), goneBooth()}})
	m, _ = press(t, next.(model), "down", "d")
	if m.confirm == nil || m.confirm.plan.Danger || !strings.Contains(m.confirm.plan.Confirm, "Forget old? Its folder is not touched.") {
		t.Fatalf("confirm %+v", m.confirm)
	}
	m, cmd := press(t, m, "y")
	next, _ = m.Update(cmd())
	m = next.(model)
	if !reflect.DeepEqual(forgot, []string{"old@docker"}) || len(f.ran) != 0 || len(f.execed) != 0 {
		t.Fatalf("forgot %v ran %v execed %v", forgot, f.ran, f.execed)
	}
	if m.status != "Forgot old." {
		t.Fatalf("status %q", m.status)
	}
}

func TestContainerKeysOnGoneBoothAreRefused(t *testing.T) {
	for _, key := range []string{keyStart, keyStop, keyRestart, keyOpen, keyPorts, keyLog, keyMessage} {
		f := &fakeDeps{}
		m, cmd := press(t, goneModel(f), "down", key)
		if cmd != nil || m.confirm != nil || m.picker != nil || m.compose != nil ||
			!strings.Contains(m.status, "old has no container") {
			t.Errorf("%s: status %q confirm %+v", key, m.status, m.confirm)
		}
		if len(f.ran)+len(f.execed)+len(f.logViewed) != 0 {
			t.Errorf("%s ran something: %v %v %v", key, f.ran, f.execed, f.logViewed)
		}
	}
}

func TestDetailPaneSkipsAGoneBooth(t *testing.T) {
	m, _ := press(t, goneModel(&fakeDeps{}), "down", keyDetail)
	if m.detail != nil {
		t.Fatalf("detail pane opened on a gone booth: %+v", m.detail)
	}
}
