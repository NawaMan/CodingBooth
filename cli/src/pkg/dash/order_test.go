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

// orderStore is an in-memory Deps.Order/SaveOrder.
type orderStore struct {
	order []lifecycle.OrderEntry
	saves int
	err   error
}

func (o *orderStore) wire(deps Deps) Deps {
	deps.Order = func() []lifecycle.OrderEntry { return append([]lifecycle.OrderEntry{}, o.order...) }
	deps.SaveOrder = func(order []lifecycle.OrderEntry) error {
		if o.err != nil {
			return o.err
		}
		o.saves++
		o.order = append([]lifecycle.OrderEntry{}, order...)
		return nil
	}
	return deps
}

func (o *orderStore) keys() []string {
	var keys []string
	for _, e := range o.order {
		keys = append(keys, e.Key)
	}
	return keys
}

// orderRepos: zeta (the dashboard's, with linked worktrees b-fix and a-idea,
// in git's order) and alpha; booths Mid (in no repository) and one on b-fix.
func orderRepos() ([]lifecycle.Booth, []lifecycle.Repo) {
	repos := []lifecycle.Repo{{
		Name: "zeta", Root: "/home/u/dev/zeta", Here: true,
		Worktrees: []lifecycle.Worktree{
			{Path: "/home/u/dev/zeta", Branch: "main", Main: true},
			{Path: "/home/u/dev/zeta.wt/b-fix", Branch: "b-fix"},
			{Path: "/home/u/dev/zeta.wt/a-idea", Branch: "a-idea"},
		},
	}, {
		Name: "alpha", Root: "/home/u/dev/alpha",
		Worktrees: []lifecycle.Worktree{{Path: "/home/u/dev/alpha", Branch: "main", Main: true}},
	}}
	booths := []lifecycle.Booth{running("Mid"), boothAt("fixer", "/home/u/dev/zeta.wt/b-fix")}
	return booths, repos
}

func orderModel(store *orderStore, booths []lifecycle.Booth, repos []lifecycle.Repo) model {
	deps := store.wire((&fakeDeps{snapshot: booths, repos: repos}).deps())
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos})
	return next.(model)
}

func TestOrderStartsByNameAndIsSaved(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	want := []string{"(none) @main", "Mid", "(none) @main", "(none) @a-idea", "fixer @b-fix"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v (alpha, Mid, zeta by name; its worktrees by name)", got, want)
	}
	if m.rows[2].repo.Name != "zeta" {
		t.Fatalf("third group is %s, want zeta", m.rows[2].repo.Name)
	}
	wantKeys := []string{"repo:/home/u/dev/alpha", "Mid@docker", "repo:/home/u/dev/zeta",
		"worktree:/home/u/dev/zeta.wt/a-idea", "worktree:/home/u/dev/zeta.wt/b-fix"}
	if got := store.keys(); !reflect.DeepEqual(got, wantKeys) {
		t.Errorf("saved = %v, want %v", got, wantKeys)
	}
	if r, _ := m.currentRow(); r.repo == nil || !r.repo.Here {
		t.Errorf("cursor on %s, want the dashboard's own repository (zeta)", rowName(r))
	}
}

func TestOrderPutsNewRowsAtTheBottom(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	saves := store.saves
	next, _ := m.Update(snapshotMsg{seq: 2, booths: append(booths, running("Aardvark")), repos: repos})
	m = next.(model)
	if got := rowName(m.rows[len(m.rows)-1]); got != "Aardvark" {
		t.Errorf("last row = %s, want the new booth Aardvark: %v", got, rowSummary(m.rows))
	}
	if store.saves != saves+1 {
		t.Errorf("saves = %d, want one more for the new booth", store.saves-saves)
	}
	// Nothing new: nothing written.
	m.Update(snapshotMsg{seq: 3, booths: append(booths, running("Aardvark")), repos: repos})
	if store.saves != saves+1 {
		t.Errorf("an unchanged snapshot saved the order again")
	}
}

func TestCtrlArrowsMoveTheGroup(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos) // cursor on zeta, the last group
	m, _ = press(t, m, "ctrl+up")
	want := []string{"(none) @main", "(none) @main", "(none) @a-idea", "fixer @b-fix", "Mid"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	if r, _ := m.currentRow(); r.repo == nil || r.repo.Name != "zeta" || !r.main {
		t.Errorf("cursor left zeta's lead row: %s", rowName(r))
	}
	if got := store.keys()[1]; got != "repo:/home/u/dev/zeta" {
		t.Errorf("saved second = %s, want zeta", got)
	}
	m, _ = press(t, m, "ctrl+up", "ctrl+up") // the second is already at the top
	if r, _ := m.currentRow(); m.cursor != 0 || r.repo.Name != "zeta" {
		t.Errorf("zeta should lead the table: %v", rowSummary(m.rows))
	}
	m, _ = press(t, m, "ctrl+down")
	if m.rows[0].repo.Name != "alpha" || m.rows[1].repo.Name != "zeta" {
		t.Errorf("ctrl+down did not move zeta back: %v", rowSummary(m.rows))
	}
	if !strings.Contains(stripANSI(m.View()), "ctrl+↑/↓ reorder") {
		t.Errorf("help line does not mention reorder")
	}
}

func TestCtrlArrowsOnAWorktreeMoveItWithinItsRepository(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "down", "down", "ctrl+up") // fixer @b-fix
	want := []string{"(none) @main", "Mid", "(none) @main", "fixer @b-fix", "(none) @a-idea"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	m, _ = press(t, m, "ctrl+up") // the main checkout stays first
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Errorf("moved past the main checkout: %v", got)
	}
	if r, _ := m.currentRow(); rowName(r) != "fixer" {
		t.Errorf("cursor on %s, want fixer", rowName(r))
	}
}

func TestReorderSkipsHiddenRowsAndKeepsTheirPlace(t *testing.T) {
	store := &orderStore{}
	hidden := &hideStore{}
	booths, repos := orderRepos()
	deps := hidden.wire(store.wire((&fakeDeps{snapshot: booths, repos: repos}).deps()))
	hidden.keys["Mid@docker"] = true
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos, hidden: deps.Hidden()})
	m, _ = press(t, next.(model), "ctrl+up") // zeta passes alpha, Mid is hidden between
	if m.rows[0].repo.Name != "zeta" {
		t.Fatalf("zeta did not move above alpha: %v", rowSummary(m.rows))
	}
	want := []string{"repo:/home/u/dev/zeta", "Mid@docker", "repo:/home/u/dev/alpha"}
	if got := store.keys()[:3]; !reflect.DeepEqual(got, want) {
		t.Errorf("saved = %v, want %v (Mid kept its place)", got, want)
	}
}

func TestReorderSaveFailureKeepsTheOrder(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	store.err = errors.New("disk full")
	before := rowSummary(m.rows)
	m, _ = press(t, m, "ctrl+up")
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, before) {
		t.Errorf("rows moved although the save failed: %v", got)
	}
	if !strings.Contains(m.status, "disk full") || !m.statusErr {
		t.Errorf("status = %q", m.status)
	}
}

func TestNoOrderStoreKeepsRowsAsBuilt(t *testing.T) {
	booths, repos := orderRepos()
	f := &fakeDeps{snapshot: booths, repos: repos}
	m := newModel(f.deps())
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos})
	m, _ = press(t, next.(model), "ctrl+down")
	want := []string{"(none) @main", "fixer @b-fix", "(none) @a-idea", "(none) @main", "Mid"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Errorf("rows = %v, want %v", got, want)
	}
}

// sepSummary is rowSummary with separators drawn as "---".
func sepSummary(rows []row) []string {
	out := rowSummary(rowsWithoutSeps(rows))
	var all []string
	i := 0
	for _, r := range rows {
		if r.sep != "" {
			all = append(all, "---")
			continue
		}
		all = append(all, out[i])
		i++
	}
	return all
}

func rowsWithoutSeps(rows []row) []row {
	var out []row
	for _, r := range rows {
		if r.sep == "" {
			out = append(out, r)
		}
	}
	return out
}

func TestSeparatorIsAddedBelowTheGroupAndSelected(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "g", "-") // on alpha
	want := []string{"(none) @main", "---", "Mid", "(none) @main", "(none) @a-idea", "fixer @b-fix"}
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	if r, _ := m.currentRow(); r.sep == "" {
		t.Errorf("cursor not on the new separator")
	}
	if got := store.keys()[1]; got != "separator:1" {
		t.Errorf("saved second = %s, want separator:1", got)
	}
	// On a linked worktree it goes below the whole repository.
	m, _ = press(t, m, "G", "-")
	if got := sepSummary(m.rows); got[len(got)-1] != "---" {
		t.Errorf("separator not below zeta's worktrees: %v", got)
	}
	if got := store.keys()[4]; got != "separator:2" {
		t.Errorf("saved = %v, want separator:2 right after zeta", store.keys())
	}
	view := stripANSI(m.View())
	if !strings.Contains(view, "────") || !strings.Contains(view, "- separator") {
		t.Errorf("separator line or help missing:\n%s", view)
	}
}

func TestSeparatorMovesAndIsDeleted(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "g", "-", "ctrl+down")
	want := []string{"(none) @main", "Mid", "---", "(none) @main", "(none) @a-idea", "fixer @b-fix"}
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	// Reopened: still there.
	m = orderModel(store, booths, repos)
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("after reopening rows = %v, want %v", got, want)
	}
	m, cmd := press(t, m, "g", "down", "down", "d")
	if cmd != nil || m.confirm != nil {
		t.Errorf("d on a separator should delete it at once")
	}
	if got := sepSummary(m.rows); len(got) != 5 || strings.Join(got, ",") != strings.Join(rowSummary(m.rows), ",") {
		t.Errorf("separator not deleted: %v", got)
	}
	for _, k := range store.keys() {
		if strings.HasPrefix(k, "separator:") {
			t.Errorf("separator still saved: %v", store.keys())
		}
	}
}

func TestSeparatorIgnoresBoothKeys(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	f := &fakeDeps{snapshot: booths, repos: repos}
	deps := store.wire(f.deps())
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos})
	m, _ = press(t, next.(model), "g", "-")
	for _, key := range []string{"s", "x", "r", "enter", "o", "p", "m", "l", "t", "e", "n", "i", "c"} {
		m, _ = press(t, m, key)
	}
	if len(f.ran)+len(f.execed) != 0 || m.confirm != nil {
		t.Errorf("a key on a separator acted: ran %v execed %v confirm %+v", f.ran, f.execed, m.confirm)
	}
}

func TestSeparatorsAreNotInTheHiddenView(t *testing.T) {
	store := &orderStore{}
	hidden := &hideStore{}
	booths, repos := orderRepos()
	deps := hidden.wire(store.wire((&fakeDeps{snapshot: booths, repos: repos}).deps()))
	hidden.keys["Mid@docker"] = true
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos, hidden: deps.Hidden()})
	m, _ = press(t, next.(model), "g", "-", "h") // h on a separator does not hide it
	if !strings.Contains(m.status, "d deletes it") || len(hidden.keys) != 1 {
		t.Errorf("h on a separator: status %q hidden %v", m.status, hidden.keys)
	}
	m, _ = press(t, m, "H")
	if got := sepSummary(m.rows); !reflect.DeepEqual(got, []string{"Mid"}) {
		t.Errorf("hidden view = %v, want only Mid", got)
	}
	m, _ = press(t, m, "-")
	if n := len(store.keys()); n != 6 {
		t.Errorf("- in the hidden view added a separator: %v", store.keys())
	}
}
