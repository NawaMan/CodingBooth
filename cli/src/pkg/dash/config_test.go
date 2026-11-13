// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"fmt"
	"reflect"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

func TestConfigPaneShowsSelectDSL(t *testing.T) {
	f := &fakeDeps{configs: map[string]ProjectConfig{
		"/home/u/dev/web/.booth": {Exists: true, Generated: true, Items: []string{"zig+zls", "Go", "aws-cli+credential"}},
	}}
	m := loaded(f, running("web"))
	m, cmd := press(t, m, "c")
	m = drain(t, m, cmd)

	view := stripANSI(m.View())
	for _, part := range []string{
		"web · Config · ~/dev/web/.booth",
		"  Select    aws-cli+credential\n            Go\n            zig+zls\n",
		"i info · c config · l log",
	} {
		if !strings.Contains(view, part) {
			t.Errorf("pane lacks %q:\n%s", part, view)
		}
	}
}

func TestConfigPaneNotGenerated(t *testing.T) {
	f := &fakeDeps{configs: map[string]ProjectConfig{
		"/home/u/dev/web/.booth": {Exists: true},
	}}
	m := loaded(f, running("web"))
	m, cmd := press(t, m, "c")
	m = drain(t, m, cmd)
	view := stripANSI(m.View())
	if !strings.Contains(view, "This .booth was not written by booth config") || strings.Contains(view, "Select") {
		t.Errorf("want the not-generated message and no selection:\n%s", view)
	}
}

func TestConfigPaneNoBoothDirAndNoTemplates(t *testing.T) {
	f := &fakeDeps{configs: map[string]ProjectConfig{
		"/home/u/dev/b/.booth": {Exists: true, Generated: true},
	}}
	m := loaded(f, running("a"), running("b"))
	m, cmd := press(t, m, "c")
	m = drain(t, m, cmd)
	if view := stripANSI(m.View()); !strings.Contains(view, "There is no .booth in this folder") {
		t.Errorf("a missing .booth must say so:\n%s", view)
	}
	m, cmd = press(t, m, "down")
	m = drain(t, m, cmd)
	if view := stripANSI(m.View()); !strings.Contains(view, "Select    (no templates selected)") {
		t.Errorf("an empty selection must say so:\n%s", view)
	}
	if want := []string{"/home/u/dev/a/.booth", "/home/u/dev/b/.booth"}; !reflect.DeepEqual(f.configRead, want) {
		t.Errorf("read %v, want %v (once per row)", f.configRead, want)
	}
}

func TestConfigUsesBoothDirAndSharesInfoSpace(t *testing.T) {
	b := running("web")
	b.BoothDir = "/elsewhere/.booth"
	f := &fakeDeps{}
	m := loaded(f, b)

	m, _ = press(t, m, "i")
	if !m.detailOpen {
		t.Fatal("i must open the info pane")
	}
	m, cmd := press(t, m, "c")
	m = drain(t, m, cmd)
	if m.detailOpen || m.detail != nil || !m.configOpen {
		t.Fatalf("c must take i's place: detail=%v config=%v", m.detailOpen, m.configOpen)
	}
	if want := []string{"/elsewhere/.booth"}; !reflect.DeepEqual(f.configRead, want) {
		t.Errorf("read %v, want the booth's own .booth dir %v", f.configRead, want)
	}
	m, _ = press(t, m, "i")
	if m.configOpen || m.config != nil || !m.detailOpen {
		t.Error("i must take c's place")
	}
	m, _ = press(t, m, "c", "c")
	if m.configOpen || m.config != nil {
		t.Error("c must close its pane")
	}
}

func TestConfigLateAnswerDropped(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("a"), running("b"))
	m, _ = press(t, m, "c", "down")
	next, _ := m.Update(configMsg{boothDir: "/home/u/dev/a/.booth", config: ProjectConfig{Exists: true, Generated: true, Items: []string{"from-a"}}})
	m = next.(model)
	if m.config.loaded {
		t.Error("a's late answer landed on b's pane")
	}
}

func TestConfigPaneManyItemsFit(t *testing.T) {
	var items []string
	for i := 0; i < 30; i++ {
		items = append(items, "python+jupyter+a-rather-long-extension-name-"+strings.Repeat("x", i))
	}
	f := &fakeDeps{configs: map[string]ProjectConfig{
		"/home/u/dev/f/.booth": {Exists: true, Generated: true, Items: items},
	}}
	m := loaded(f, running("a"), running("b"), running("c"), running("d"), running("e"), running("f"))
	next, _ := m.Update(tea.WindowSizeMsg{Width: 60, Height: 24})
	m = next.(model)
	m, cmd := press(t, m, "G", "c")
	m = drain(t, m, cmd)
	view := stripANSI(m.View())
	if got := strings.Count(view, "\n") + 1; got > 24 {
		t.Errorf("view is %d lines on a 24-line screen:\n%s", got, view)
	}
	if !strings.Contains(view, "› f") {
		t.Errorf("cursor row hidden:\n%s", view)
	}
	fit := m.configItemsFit()
	if want := fmt.Sprintf("… and %d more", len(items)-(fit-1)); !strings.Contains(view, want) {
		t.Errorf("want %q:\n%s", want, view)
	}
	if body := m.configBody(); len(body) != fit {
		t.Errorf("body is %d lines, want %d", len(body), fit)
	}
	for _, line := range strings.Split(view, "\n") {
		if w := len([]rune(line)); w > 60 {
			t.Errorf("line wider than the screen (%d): %q", w, line)
		}
	}
}

func TestConfigNameMatchesNameCell(t *testing.T) {
	repo := &lifecycle.Repo{Name: "proj", Root: "/p"}
	main := lifecycle.Worktree{Path: "/p", Branch: "main", Main: true}
	linked := lifecycle.Worktree{Path: "/p/w", Branch: "feat"}
	b := running("web")
	cases := map[string]row{
		"proj": {repo: repo, worktree: &main, main: true},
		"web":  {repo: repo, worktree: &main, main: true, booth: &b},
	}
	for want, r := range cases {
		if got := configName(r); got != want {
			t.Errorf("configName = %q, want %q", got, want)
		}
	}
	if got, want := configName(row{repo: repo, worktree: &linked}), linked.Name(); got != want {
		t.Errorf("a linked worktree's name = %q, want %q", got, want)
	}
}
