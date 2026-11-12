// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"errors"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

var drainWait = 50 * time.Millisecond

// drain runs cmd and feeds what it produces back into m, without following
// timers (a tick would reload forever).
func drain(t *testing.T, m model, cmd tea.Cmd) model {
	t.Helper()
	if cmd == nil {
		return m
	}
	done := make(chan tea.Msg, 1)
	go func() { done <- cmd() }()
	var msg tea.Msg
	select {
	case msg = <-done:
	case <-time.After(drainWait):
		return m // a timer
	}
	switch msg := msg.(type) {
	case nil, tickMsg, detailTickMsg:
		return m
	case tea.BatchMsg:
		for _, c := range msg {
			m = drain(t, m, c)
		}
		return m
	default:
		next, more := m.Update(msg)
		return drain(t, next.(model), more)
	}
}

func detailBooth() lifecycle.Booth {
	b := running("web")
	b.StartedAt = "2026-11-10T09:30:00.123456789Z"
	return b
}

func TestDetailPaneShowsEveryPart(t *testing.T) {
	f := &fakeDeps{
		stats: lifecycle.BoothStats{CPU: "1.5%", Memory: "300MiB / 8GiB", MemPerc: "3.6%"},
		state: lifecycle.BoothState{
			Presence: lifecycle.BoothPresence{Viewers: 2, Background: 1, Expected: 1},
			Idle:     lifecycle.BoothIdle{Enabled: true, IdleTime: 1800, ShutdownTime: 60},
		},
		ports:   []lifecycle.ExposedPort{{ContainerPort: 10000, HostPort: 10000, Proto: "tcp", Kind: "front door", Live: true}},
		pending: []lifecycle.PendingMessage{{ID: "m1", Title: "Deploy?", Type: "yes-no"}},
		logs:    "one\n\x1b[31mtwo\x1b[0m\nprogress 10%\rprogress 100%\n",
	}
	m := loaded(f, detailBooth())
	m, cmd := press(t, m, "i")
	m = drain(t, m, cmd)

	sort.Strings(f.detailed)
	want := []string{"logs:web", "pending:web", "state:web", "stats:web"}
	if !reflect.DeepEqual(f.detailed, want) || len(f.portsFor) != 1 {
		t.Fatalf("asked for %v ports %v, want %v and ports once", f.detailed, f.portsFor, want)
	}
	view := stripANSI(m.View())
	for _, part := range []string{
		"web · Running · up 2h · CPU 1.5% · MEM 300MiB / 8GiB (3.6%)",
		"Viewers   2 viewing (1 in background)",
		"Idle      asks after 30m idle, then shuts down 1m later",
		"Ports     10000 http://localhost:10000",
		"Messages  1 waiting: Deploy?",
		"Logs      last 3 lines",
		"    one\n    two\n    progress 100%\n",
		"i info · l log",
		"↑/↓ move · s start",
	} {
		if !strings.Contains(view, part) {
			t.Errorf("pane lacks %q:\n%s", part, view)
		}
	}
}

func TestDetailPaneStoppedBoothSkipsLiveParts(t *testing.T) {
	f := &fakeDeps{logs: "bye\n"}
	b := stopped("db")
	b.FinishedAt = "2026-11-10T11:00:00Z"
	m := loaded(f, b)
	m, cmd := press(t, m, "i")
	m = drain(t, m, cmd)

	sort.Strings(f.detailed)
	if want := []string{"logs:db", "pending:db"}; !reflect.DeepEqual(f.detailed, want) || len(f.portsFor) != 0 {
		t.Fatalf("asked for %v ports %v, want only %v", f.detailed, f.portsFor, want)
	}
	view := stripANSI(m.View())
	for _, part := range []string{"db · Stopped · stopped 1h ago", "Viewers   -", "Messages  none waiting", "    bye"} {
		if !strings.Contains(view, part) {
			t.Errorf("pane lacks %q:\n%s", part, view)
		}
	}
}

func TestDetailPartFailureShowsReasonOthersStay(t *testing.T) {
	f := &fakeDeps{statsErr: errors.New("not available on engine apple"), stateErr: errors.New("its message API did not answer"), logs: "ok\n"}
	m := loaded(f, detailBooth())
	m, cmd := press(t, m, "i")
	m = drain(t, m, cmd)
	view := stripANSI(m.View())
	for _, part := range []string{"stats: not available on engine apple", "Viewers   - (its message API did not answer)", "    ok"} {
		if !strings.Contains(view, part) {
			t.Errorf("pane lacks %q:\n%s", part, view)
		}
	}
}

func TestDetailFollowsCursorAndDropsLateAnswers(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("a"), running("b"))
	m, cmd := press(t, m, "i")
	if m.detail == nil || m.detail.key != "a@docker" {
		t.Fatalf("pane = %+v", m.detail)
	}
	oldGen := m.detail.gen

	m, _ = press(t, m, "down")
	if m.detail.key != "b@docker" || m.detail.gen == oldGen {
		t.Fatalf("pane did not follow the cursor: %+v", m.detail)
	}
	// a's answers arrive after the move: they must not land on b's pane.
	next, _ := m.Update(detailMsg{gen: oldGen, apply: func(p *detailPane) { p.logs.set("from a", nil) }})
	m = next.(model)
	if m.detail.logs.loaded {
		t.Error("a late answer for the old booth landed on the new pane")
	}
	_ = cmd

	m, _ = press(t, m, "i")
	if m.detailOpen || m.detail != nil {
		t.Error("i must close the pane")
	}
}

func TestDetailTickReloadsOnlyWhenIdle(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, detailBooth())
	m, _ = press(t, m, "i")
	seq := m.detailSeq
	if m.detail.inflight == 0 {
		t.Fatal("opening must start a load")
	}
	// A tick while the load is out asks for nothing more.
	next, _ := m.Update(detailTickMsg{seq: seq})
	m = next.(model)
	if m.detail.inflight != 5 {
		t.Errorf("inflight = %d after a tick during a load, want 5", m.detail.inflight)
	}
	// A tick from a pane opened before is ignored once closed.
	m, _ = press(t, m, "i")
	next, cmd := m.Update(detailTickMsg{seq: seq})
	if cmd != nil && next.(model).detail != nil {
		t.Error("a closed pane must not reload")
	}
}

func TestDetailPaneShrinksTableKeepsCursor(t *testing.T) {
	f := &fakeDeps{}
	booths := []lifecycle.Booth{running("a"), running("b"), running("c"), running("d"), running("e"), running("f")}
	m := loaded(f, booths...)
	next, _ := m.Update(tea.WindowSizeMsg{Width: 120, Height: 24})
	m = next.(model)
	m, _ = press(t, m, "G", "i")
	if got := strings.Count(stripANSI(m.View()), "\n") + 1; got > 24 {
		t.Errorf("view is %d lines on a 24-line screen:\n%s", got, stripANSI(m.View()))
	}
	if !strings.Contains(stripANSI(m.View()), "› f") {
		t.Errorf("cursor row hidden:\n%s", stripANSI(m.View()))
	}
}

func TestDetailTexts(t *testing.T) {
	now := time.Date(2026, 11, 11, 12, 0, 0, 0, time.UTC)
	cases := map[string]string{
		viewersText(lifecycle.BoothPresence{}):                                           "nobody",
		viewersText(lifecycle.BoothPresence{Viewers: 1}):                                 "1 viewing",
		idleText(lifecycle.BoothIdle{}, now):                                             "off",
		idleText(lifecycle.BoothIdle{Enabled: true, Disabled: true}, now):                "disabled until resumed",
		idleText(lifecycle.BoothIdle{Enabled: true, PauseUntil: now.Unix() + 3600}, now): "paused until 13:00",
		shortDuration(45):                  "45s",
		shortDuration(5400):                "1h30m",
		shortDuration(7200):                "2h",
		since("0001-01-01T00:00:00Z", now): "",
		since("", now):                     "",
	}
	for got, want := range cases {
		if got != want {
			t.Errorf("got %q, want %q", got, want)
		}
	}
	if got := logTail("a\n\nb\nc\n", 2); !reflect.DeepEqual(got, []string{"b", "c"}) {
		t.Errorf("logTail = %v", got)
	}
}
