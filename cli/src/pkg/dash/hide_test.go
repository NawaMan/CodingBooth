// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// hideStore is an in-memory Deps.Hidden/Hide.
type hideStore struct {
	keys  map[string]bool
	paths map[string]string
	err   error
}

func (h *hideStore) wire(deps Deps) Deps {
	if h.keys == nil {
		h.keys, h.paths = map[string]bool{}, map[string]string{}
	}
	deps.Hidden = func() map[string]bool {
		out := map[string]bool{}
		for k := range h.keys {
			out[k] = true
		}
		return out
	}
	deps.Hide = func(key, path string, hidden bool) error {
		if h.err != nil {
			return h.err
		}
		if hidden {
			h.keys[key], h.paths[key] = true, path
		} else {
			delete(h.keys, key)
		}
		return nil
	}
	return deps
}

// hideModel shows web, api and db, with the store's keys hidden.
func hideModel(store *hideStore) model {
	booths := []lifecycle.Booth{running("web"), running("api"), running("db")}
	deps := store.wire((&fakeDeps{snapshot: booths}).deps())
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, hidden: deps.Hidden()})
	return next.(model)
}

func rowNames(m model) []string {
	var names []string
	for _, r := range m.rows {
		names = append(names, rowName(r))
	}
	return names
}

func TestHideTakesTheRowOutAndRemembersIt(t *testing.T) {
	store := &hideStore{}
	m, _ := press(t, hideModel(store), "down", "h")
	if got, want := rowNames(m), []string{"web", "db"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	if !store.keys["api@docker"] || store.paths["api@docker"] != "/home/u/dev/api" {
		t.Errorf("store = %v %v, want api@docker with its code path", store.keys, store.paths)
	}
	if r, _ := m.currentRow(); rowName(r) != "db" {
		t.Errorf("cursor on %s, want the next row (db)", rowName(r))
	}
	view := stripANSI(m.View())
	if !strings.Contains(view, "1 hidden") || !strings.Contains(view, "Hid api. H shows the hidden rows.") {
		t.Errorf("title or status missing:\n%s", view)
	}
}

func TestHiddenViewShowsOnlyHiddenAndUnhides(t *testing.T) {
	store := &hideStore{keys: map[string]bool{"api@docker": true}, paths: map[string]string{}}
	m := hideModel(store)
	if got := rowNames(m); !reflect.DeepEqual(got, []string{"web", "db"}) {
		t.Fatalf("hidden from the start: rows = %v", got)
	}
	m, _ = press(t, m, "H")
	if got := rowNames(m); !reflect.DeepEqual(got, []string{"api"}) {
		t.Fatalf("H: rows = %v, want [api]", got)
	}
	view := stripANSI(m.View())
	if !strings.Contains(view, "showing 1 hidden") || !strings.Contains(view, "h unhide · H back") {
		t.Errorf("H view not marked:\n%s", view)
	}

	m, _ = press(t, m, "h")
	if len(m.rows) != 0 || store.keys["api@docker"] {
		t.Fatalf("after unhide: rows %v, store %v", rowNames(m), store.keys)
	}
	if view := stripANSI(m.View()); !strings.Contains(view, "Nothing is hidden.") {
		t.Errorf("empty H view:\n%s", view)
	}

	m, _ = press(t, m, "H")
	if got := rowNames(m); !reflect.DeepEqual(got, []string{"web", "api", "db"}) {
		t.Errorf("back: rows = %v", got)
	}
}

func TestEveryRowHiddenSaysSo(t *testing.T) {
	store := &hideStore{}
	m, _ := press(t, hideModel(store), "h", "h", "h")
	if len(m.rows) != 0 {
		t.Fatalf("rows = %v", rowNames(m))
	}
	if view := stripANSI(m.View()); !strings.Contains(view, "Every row is hidden (3). H shows them.") {
		t.Errorf("view:\n%s", view)
	}
}

func TestHideFailureKeepsTheRow(t *testing.T) {
	store := &hideStore{err: errors.New("disk full")}
	m, _ := press(t, hideModel(store), "h")
	if got := rowNames(m); len(got) != 3 {
		t.Errorf("rows = %v, want all three", got)
	}
	if !m.statusErr || !strings.Contains(m.status, "Could not hide web: disk full") {
		t.Errorf("status = %q (err %v)", m.status, m.statusErr)
	}
}

func TestSnapshotStartedBeforeAHideDoesNotBringTheRowBack(t *testing.T) {
	store := &hideStore{}
	m := hideModel(store)
	inFlight := m.fetch(2)() // read before the hide: nothing hidden
	m.fetchSeq = 2
	m, _ = press(t, m, "h")
	next, _ := m.Update(inFlight)
	m = next.(model)
	if got := rowNames(m); !reflect.DeepEqual(got, []string{"api", "db"}) {
		t.Errorf("rows = %v; the old snapshot un-hid web", got)
	}
}

func TestHidingABareWorktreeLetsItsLaterBoothShow(t *testing.T) {
	repo := lifecycle.Repo{Name: "proj", Root: "/home/u/dev/proj", Worktrees: []lifecycle.Worktree{
		{Path: "/home/u/dev/proj", Branch: "main", Main: true},
		{Path: "/home/u/dev/proj/worktree/feat", Branch: "feat"},
	}}
	store := &hideStore{}
	deps := store.wire((&fakeDeps{}).deps())
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, repos: []lifecycle.Repo{repo}})
	m, _ = press(t, next.(model), "down", "h")
	if !store.keys["worktree:/home/u/dev/proj/worktree/feat"] || len(m.rows) != 1 {
		t.Fatalf("store %v, rows %v", store.keys, rowNames(m))
	}

	feat := running("feat")
	feat.CodePath = "/home/u/dev/proj/worktree/feat"
	next, _ = m.Update(snapshotMsg{seq: 2, booths: []lifecycle.Booth{feat}, repos: []lifecycle.Repo{repo},
		hidden: deps.Hidden(), hiddenGen: m.hiddenGen})
	if got := rowNames(next.(model)); !reflect.DeepEqual(got, []string{"main", "feat"}) {
		t.Errorf("rows = %v; a booth started on a hidden worktree should show", got)
	}
}

func TestHideKeysOffWithoutAStore(t *testing.T) {
	m, cmd := press(t, loaded(&fakeDeps{}, running("web")), "h", "H")
	if cmd != nil || len(m.rows) != 1 || m.showHidden {
		t.Errorf("h/H did something without a store: rows %v showHidden %v", rowNames(m), m.showHidden)
	}
	if strings.Contains(stripANSI(m.View()), "h hide") {
		t.Errorf("help offers h without a store")
	}
}
